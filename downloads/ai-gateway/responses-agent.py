"""Source-derived interactive Responses/MCP template. Requires the openai package.

No request runs until main() is invoked and the user enters a prompt.
Runtime access keys are gateway-wide. Review the MCP server's tools and policies.
The original demonstration used approval='never'; this template requires an
explicit choice and implements the safer 'always' approval flow as well.
"""
import os
from urllib.parse import quote, urlsplit


def required(name):
    value = os.getenv(name)
    if not value or not value.strip() or value.startswith("YOUR_"):
        raise RuntimeError(f"Required environment variable is missing: {name}")
    return value.strip()


def main():
    from openai import OpenAI

    host = required("AI_GATEWAY_HOST").rstrip("/")
    parsed = urlsplit(host)
    if (parsed.scheme != "https" or not parsed.hostname or parsed.username
            or parsed.password or parsed.path or parsed.query or parsed.fragment):
        raise RuntimeError("AI_GATEWAY_HOST must be an HTTPS origin without credentials or a path")
    api_key = required("AI_GATEWAY_API_KEY")
    model = required("AI_GATEWAY_MODEL_NAME")
    server = required("AI_GATEWAY_MCP_SERVER_NAME")
    label = required("AI_GATEWAY_MCP_SERVER_LABEL")
    approval = required("AI_GATEWAY_MCP_APPROVAL")
    if approval not in {"always", "never"}:
        raise RuntimeError("AI_GATEWAY_MCP_APPROVAL must be always or never")
    client = OpenAI(
        base_url=f"{host}/default/models/openai/v1",
        api_key="unused",  # SDK-required dummy; gateway authentication uses api-key.
        default_headers={"api-key": api_key},
    )
    tool = {
        "type": "mcp",
        "server_label": label,
        "server_url": f"{host}/default/toolservers/{quote(server, safe='')}/mcp",
        "headers": {"api-key": api_key},
        "require_approval": approval,
    }
    previous_response_id = None
    while True:
        user_text = input("User> ").strip()
        if not user_text:
            break
        response = client.responses.create(
            model=model,
            input=[{"role": "user", "content": user_text}],
            tools=[tool],
            previous_response_id=previous_response_id,
        )
        while True:
            approvals = []
            for item in response.output:
                if item.type == "mcp_list_tools":
                    print(f"  [MCP] Available tools: {[t.name for t in item.tools]}")
                elif item.type == "mcp_call":
                    status = "success" if item.error is None else "error"
                    print(f"  [MCP] Call: {item.name} -> {status}")
                elif item.type == "mcp_approval_request":
                    print(f"  [MCP] Approval requested: {item.name}({item.arguments})")
                    approved = input("Approve this tool call? Type yes: ").strip().lower() == "yes"
                    approvals.append({
                        "type": "mcp_approval_response",
                        "approval_request_id": item.id,
                        "approve": approved,
                    })
            if not approvals:
                break
            response = client.responses.create(
                model=model, input=approvals, tools=[tool],
                previous_response_id=response.id,
            )
        print(f"Model> {response.output_text}\n")
        previous_response_id = response.id


if __name__ == "__main__":
    main()
