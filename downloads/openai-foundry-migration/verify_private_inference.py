#!/usr/bin/env python3
"""Source-derived diagnostic; no infrastructure changes, one billable inference."""

import argparse
import hashlib
import http.client
import ipaddress
import json
import pathlib
import socket
import subprocess
import sys
import urllib.request
from urllib.parse import urlencode, urlsplit


class CheckFailure(Exception):
    pass


def configuration(endpoint, subnet):
    parsed = urlsplit(endpoint)
    if (
        parsed.scheme != "https"
        or not parsed.hostname
        or not parsed.hostname.endswith(".openai.azure.com")
        or parsed.username
        or parsed.password
        or parsed.port not in (None, 443)
        or parsed.path not in ("", "/")
        or parsed.query
        or parsed.fragment
    ):
        raise CheckFailure("endpoint_configuration")
    network = ipaddress.ip_network(subnet, strict=True)
    if network.version != 4 or not network.is_private:
        raise CheckFailure("subnet_configuration")
    return parsed.hostname, network


def run(args):
    host, network = configuration(args.endpoint, args.pe_subnet)
    print("client_sha256=" + hashlib.sha256(pathlib.Path(__file__).read_bytes()).hexdigest())
    addresses = sorted({
        entry[4][0]
        for entry in socket.getaddrinfo(
            host, 443, family=socket.AF_INET, type=socket.SOCK_STREAM
        )
    })
    if not addresses or any(ipaddress.ip_address(ip) not in network for ip in addresses):
        raise CheckFailure("dns_outside_expected_subnet")
    print("dns_in_expected_subnet=true")

    query = urlencode({
        "api-version": "2018-02-01",
        "resource": "https://cognitiveservices.azure.com/",
    })
    request = urllib.request.Request(
        "http://169.254.169.254/metadata/identity/oauth2/token?" + query,
        headers={"Metadata": "true"},
    )
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    with opener.open(request, timeout=20) as response:
        token = json.load(response)["access_token"]
    if not isinstance(token, str) or not token or any(c in token for c in '\r\n"\\'):
        raise CheckFailure("token_format")

    payload = {
        "model": args.deployment,
        "messages": [{"role": "user", "content": "Reply with a short synthetic greeting."}],
        "reasoning_effort": "minimal",
        "max_completion_tokens": 256,
    }
    # Pin a checked address while retaining the hostname for TLS verification.
    result = subprocess.run(
        [
            "curl", "-q", "--silent", "--show-error", "--noproxy", "*",
            "--connect-timeout", "20", "--max-time", "180",
            "--resolve", f"{host}:443:{addresses[0]}",
            "--config", "-", "--header", "Content-Type: application/json",
            "--data-binary", json.dumps(payload),
            "--write-out", "\n%{http_code} %{remote_ip}",
            f"https://{host}/openai/v1/chat/completions",
        ],
        input=f'header = "Authorization: Bearer {token}"\n',
        text=True, capture_output=True, check=False, timeout=190,
    )
    if result.returncode:
        raise CheckFailure("transport_failure")
    body, metrics = result.stdout.rsplit("\n", 1)
    status, remote_ip = metrics.split()
    if not status.isdigit() or len(status) != 3:
        raise CheckFailure("invalid_http_status")
    print("http_status=" + status)
    if ipaddress.ip_address(remote_ip) not in network or remote_ip != addresses[0]:
        raise CheckFailure("unexpected_connected_address")
    print("connected_to_checked_private_address=true")
    if status != "200":
        raise CheckFailure("inference_http_failure")
    choice = json.loads(body)["choices"][0]
    content = choice["message"].get("content")
    if choice["finish_reason"] != "stop" or not isinstance(content, str) or not content.strip():
        raise CheckFailure("incomplete_text_response")
    print("complete_nonempty_text=true")
    print("result=PASS")


def main():
    parser = argparse.ArgumentParser(
        description=(
            "One source-derived private-path inference check on an Azure VM with a "
            "system-assigned managed identity. Does not modify Azure resources. "
            "Inference consumes quota and may incur cost. Prints no endpoint, "
            "deployment, address, token, prompt response, or raw error body."
        )
    )
    parser.add_argument("--endpoint", help="Existing HTTPS Azure OpenAI resource endpoint")
    parser.add_argument("--deployment", help="Existing deployment name, not a model catalog ID")
    parser.add_argument("--pe-subnet", help="Expected private endpoint IPv4 subnet in CIDR notation")
    parser.add_argument(
        "--run-inference", action="store_true",
        help="Explicitly permit DNS, IMDS token acquisition and one inference request",
    )
    args = parser.parse_args()
    if not args.run_inference:
        parser.error("--run-inference is required; no network calls were made")
    if not args.endpoint or not args.deployment or not args.pe_subnet:
        parser.error("--endpoint, --deployment and --pe-subnet are required")
    try:
        run(args)
    except CheckFailure as error:
        print("result=FAIL reason=" + str(error), file=sys.stderr)
        return 1
    except (OSError, ValueError, KeyError, IndexError, TypeError,
            subprocess.SubprocessError, http.client.HTTPException):
        # Raw exceptions can contain resource names, IP addresses or response bodies.
        print("result=FAIL reason=local_or_protocol_error", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
