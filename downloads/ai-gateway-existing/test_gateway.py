"""REFERENCE ONLY: sanitized original unit tests; not runnable standalone.

Missing dependencies: original scripts/poclib.py, configure-apim.py,
apply-chat-policy.py, validate-gateway.py, monitoring.py, legacy_usage.py,
and their original configuration, ownership state, and policy templates.
Set POC_SOURCE_ROOT to a separately reviewed compatible project before use.
No helpers are supplied or fabricated here; no cloud execution is claimed.
Resource/deployment identifiers are placeholders. Other test names, hosts,
and secret-like strings are synthetic fixtures, never production credentials.
"""
import importlib.util
import json
import os
from pathlib import Path
import sys
import time
import unittest
from unittest.mock import MagicMock, patch
from xml.etree import ElementTree

source_root = os.getenv("POC_SOURCE_ROOT")
if not source_root or not source_root.strip():
    raise RuntimeError("Reference-only tests require POC_SOURCE_ROOT; original helpers are not included.")
ROOT = Path(source_root).expanduser().resolve()
for filename in ("poclib.py", "configure-apim.py", "apply-chat-policy.py",
                 "validate-gateway.py", "monitoring.py", "legacy_usage.py"):
    if not (ROOT / "scripts" / filename).is_file():
        raise RuntimeError(f"Missing original dependency: scripts/{filename}; tests are not standalone.")
sys.path.insert(0, str(ROOT / "scripts"))
import poclib


def module(name, filename):
    spec = importlib.util.spec_from_file_location(name, ROOT / "scripts" / filename)
    loaded = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(loaded)
    return loaded


configure = module("configure", "configure-apim.py")
apply_chat = module("apply_chat", "apply-chat-policy.py")
validate = module("validate", "validate-gateway.py")


def with_store_override(text):
    root = ElementTree.fromstring(text)
    body = ElementTree.SubElement(root.find("inbound"), "set-body")
    body.text = ('@{ var body = context.Request.Body.As<JObject>(preserveContent: true); '
                 'body["store"] = false; return body.ToString(); }')
    return ElementTree.tostring(root, encoding="unicode")


class GatewayTests(unittest.TestCase):
    def setUp(self):
        self.config = {
            "subscriptionId": "YOUR_SUBSCRIPTION_ID",
            "resourceGroup": "YOUR_RESOURCE_GROUP", "apimName": "apim-test",
            "accountNames": ["account-one", "account-two"],
            "deploymentName": "YOUR_DEPLOYMENT_NAME", "ownershipTag": "test-owner",
        }
        self.resources = dict(configure.build_resources(
            self.config, "https://cognitiveservices.azure.com"))

    def test_backends_and_pool(self):
        base = poclib.apim_id(self.config)
        for index in (1, 2):
            props = self.resources[f"{base}/backends/foundry-{index}"]["properties"]
            self.assertEqual(props["tls"], {"validateCertificateName": True,
                                           "validateCertificateChain": True})
            rule = props["circuitBreaker"]["rules"][0]
            self.assertEqual(rule["failureCondition"]["statusCodeRanges"], [{"min": 429, "max": 429}])
            self.assertEqual(rule["failureCondition"]["count"], 1)
            self.assertTrue(rule["acceptRetryAfter"])
        pool = self.resources[f"{base}/backends/foundry-pool"]["properties"]
        self.assertNotIn("circuitBreaker", pool)
        self.assertEqual(len(pool["pool"]["services"]), 2)
        self.assertTrue(all(s["priority"] == s["weight"] == 1 for s in pool["pool"]["services"]))
        self.assertNotIn("sessionAffinity", pool["pool"])

    def test_policy_all_operations(self):
        for op, _, path, responses, legacy, backend in configure.operations(self.config):
            text = configure.policy(self.config, path, legacy, backend,
                                    "https://cognitiveservices.azure.com", responses=responses)
            root = ElementTree.fromstring(text)
            self.assertEqual(root.findall(".//validate-content"), [])
            self.assertIsNone(root.find("inbound/choose"))
            body_policies = root.findall(".//set-body")
            self.assertEqual(body_policies, [])
            retry = root.find("backend/retry")
            self.assertEqual(retry.attrib["count"], "1")
            self.assertIn("StatusCode == 429", retry.attrib["condition"])
            self.assertNotIn("Elapsed", retry.attrib["condition"])
            self.assertNotIn("500", retry.attrib["condition"])
            self.assertIn("true" if backend == "foundry-pool" else "false", retry.attrib["condition"])
            self.assertEqual(retry.find("set-backend-service").attrib["backend-id"], backend)
            forward = retry.find("forward-request").attrib
            self.assertEqual(forward["buffer-request-body"], "true")
            self.assertEqual(forward["buffer-response"], "false")
            self.assertEqual(forward["follow-redirects"], "false")
            self.assertEqual(forward["timeout"], "60")
            self.assertIsNone(root.find("backend/base"))
            self.assertNotIn("__", text)
            metadata = root.findall(".//trace/metadata")
            self.assertFalse(any("Body" in m.attrib["value"] or "Authorization" in m.attrib["value"]
                                 for m in metadata))
            for name, header in (("retryAfter", "Retry-After"), ("retryAfterMs", "retry-after-ms")):
                value = root.find(f".//trace/metadata[@name='{name}']").attrib["value"]
                self.assertEqual(
                    value,
                    f'@{{ var header = context.Response.Headers.GetValueOrDefault("{header}", ""); '
                    'return string.IsNullOrWhiteSpace(header) ? "not-present" : header; }')

    def test_single_backend_stage_only_writes_two_backends(self):
        resources = configure.build_single_backends(self.config)
        expected = dict(resources)
        self.assertEqual(len(resources), 2)
        self.assertTrue(all(body["properties"]["type"] == "Single"
                            for _, body in resources))

        def fake_arm(method, resource_id, body=None):
            if method == "get" and resource_id.endswith("/backends"):
                return {"value": []}
            self.assertIn(resource_id, expected)
            return expected[resource_id]

        with patch.object(configure, "arm", side_effect=fake_arm) as arm:
            configure.apply_single_backends(self.config)
        writes = [call.args[1] for call in arm.call_args_list if call.args[0] != "get"]
        self.assertEqual(writes, list(expected))

    def test_single_backend_stage_preserves_existing_and_rejects_drift(self):
        resources = configure.build_single_backends(self.config)
        entries = [{"name": path.rsplit("/", 1)[1], **body} for path, body in resources]
        expected = dict(resources)

        def fake_arm(method, resource_id, body=None):
            self.assertEqual(method, "get")
            if resource_id.endswith("/backends"):
                return {"value": entries}
            return expected[resource_id]

        with patch.object(configure, "arm", side_effect=fake_arm):
            configure.apply_single_backends(self.config)
            entries[1]["properties"]["description"] = "foreign"
            with self.assertRaises(RuntimeError):
                configure.apply_single_backends(self.config)

    def test_pool_stage_only_writes_pool_and_preserves_existing(self):
        singles = configure.build_single_backends(self.config)
        pool_id, pool_body = configure.build_pool(self.config)
        entries = [{"name": path.rsplit("/", 1)[1], **body} for path, body in singles]

        def fake_arm(method, resource_id, body=None):
            if method == "get" and resource_id.endswith("/backends"):
                return {"value": entries}
            self.assertEqual(resource_id, pool_id)
            return pool_body

        with patch.object(configure, "arm", side_effect=fake_arm) as arm:
            configure.apply_pool(self.config)
            writes = [call.args for call in arm.call_args_list if call.args[0] != "get"]
            self.assertEqual(writes, [("put", pool_id, pool_body)])
            entries.append({"name": "foundry-pool", **pool_body})
            arm.reset_mock()
            configure.apply_pool(self.config)
            self.assertTrue(all(call.args[0] == "get" for call in arm.call_args_list))

    def test_pool_stage_rejects_missing_member_and_existing_pool_drift(self):
        singles = configure.build_single_backends(self.config)
        entries = [{"name": path.rsplit("/", 1)[1], **body} for path, body in singles]
        cases = [entries[:1], entries + [{
            "name": "foundry-pool", "properties": {"type": "Pool", "description": "foreign"},
        }]]
        for inventory in cases:
            with self.subTest(inventory=inventory):
                with patch.object(configure, "arm", return_value={"value": inventory}) as arm:
                    with self.assertRaises(RuntimeError):
                        configure.apply_pool(self.config)
                    self.assertTrue(all(call.args[0] == "get" for call in arm.call_args_list))

    def test_api_stage_only_writes_api_and_two_operations(self):
        resources = dict(configure.build_api_operations(self.config))
        api_id = next(iter(resources))
        self.assertEqual(len(resources), 3)
        self.assertNotIn("serviceUrl", resources[api_id]["properties"])
        self.assertTrue(all("/policies/" not in path and "/schemas/" not in path
                            for path in resources))

        def fake_arm(method, resource_id, body=None):
            if method == "get" and resource_id.endswith("/apis"):
                return {"value": []}
            self.assertIn(resource_id, resources)
            return resources[resource_id]

        with patch.object(configure, "arm", side_effect=fake_arm) as arm:
            configure.apply_api_operations(self.config)
        self.assertEqual([call.args[1] for call in arm.call_args_list
                          if call.args[0] == "put"], list(resources))

    def test_api_stage_preserves_existing_and_rejects_path_collision(self):
        resources = dict(configure.build_api_operations(self.config))
        api_id = next(iter(resources))
        api_entry = {"name": poclib.API_ID, **resources[api_id]}
        entries = [{"name": path.rsplit("/", 1)[1], **body}
                   for path, body in resources.items() if path != api_id]

        def fake_arm(method, resource_id, body=None):
            self.assertEqual(method, "get")
            if resource_id.endswith("/apis"):
                return {"value": [api_entry]}
            if resource_id.endswith("/operations"):
                return {"value": entries}
            return resources[resource_id]

        with patch.object(configure, "arm", side_effect=fake_arm):
            configure.apply_api_operations(self.config)
            api_entry["name"] = "another-api"
            with self.assertRaises(RuntimeError):
                configure.apply_api_operations(self.config)

    def test_chat_policy_apply_only_writes_chat_operation(self):
        api_id = poclib.apim_id(self.config) + "/apis/" + poclib.API_ID
        target = api_id + "/operations/chat/policies/policy"
        text = configure.policy(self.config, "/openai/v1/chat/completions", False,
                                poclib.POOL_ID, "https://cognitiveservices.azure.com",
                                responses=False)
        resources = dict(configure.build_api_operations(self.config))
        pool_id, pool = configure.build_pool(self.config)
        resources[pool_id] = pool
        resources[api_id + "/operations/chat/policies"] = {"value": []}
        resources[target] = {"properties": {"value": text}}

        def fake_arm(method, resource_id, body=None, **kwargs):
            if method == "put":
                self.assertEqual(resource_id, target)
                self.assertEqual(body["properties"]["value"], text)
            if method == "get" and resource_id == target:
                self.assertEqual(kwargs, {"query": {"format": "rawxml"}})
            return resources[resource_id]

        with patch.object(apply_chat, "arm", side_effect=fake_arm) as arm:
            apply_chat.apply_chat(self.config, text)
            writes = [call.args[1] for call in arm.call_args_list if call.args[0] == "put"]
            self.assertEqual(writes, [target])
            resources[api_id + "/operations/chat/policies"] = {"value": [{"name": "policy"}]}
            arm.reset_mock()
            apply_chat.apply_chat(self.config, text)
            self.assertTrue(all(call.args[0] == "get" for call in arm.call_args_list))
            resources[target] = {"properties": {"value": "<policies />"}}
            arm.reset_mock()
            with self.assertRaises(RuntimeError):
                apply_chat.apply_chat(self.config, text)
            self.assertTrue(all(call.args[0] == "get" for call in arm.call_args_list))

    def test_responses_policy_only_writes_responses_and_preserves_existing(self):
        api_id = poclib.apim_id(self.config) + "/apis/" + poclib.API_ID
        operation_id = api_id + "/operations/responses"
        target = operation_id + "/policies/policy"
        text = configure.policy(self.config, "/openai/v1/responses", False,
                                poclib.POOL_ID, "https://cognitiveservices.azure.com",
                                responses=True)
        resources = dict(configure.build_api_operations(self.config))
        pool_id, pool = configure.build_pool(self.config)
        resources[pool_id] = pool
        resources[operation_id + "/policies"] = {"value": []}

        def fake_arm(method, resource_id, body=None, **kwargs):
            if method == "put":
                self.assertEqual(resource_id, target)
                self.assertEqual(body["properties"]["value"], text)
                resources[resource_id] = body
                resources[operation_id + "/policies"]["value"] = [{"name": "policy"}]
            if method == "get" and resource_id == target:
                self.assertEqual(kwargs, {"query": {"format": "rawxml"}})
            return resources[resource_id]

        with patch.object(apply_chat, "arm", side_effect=fake_arm) as arm:
            apply_chat.apply_chat(self.config, text, responses=True)
            self.assertEqual([c.args[1] for c in arm.call_args_list if c.args[0] == "put"], [target])
            arm.reset_mock()
            apply_chat.apply_chat(self.config, text, responses=True)
            self.assertTrue(all(c.args[0] == "get" for c in arm.call_args_list))
            resources[target] = {"properties": {"value": "<policies />"}}
            arm.reset_mock()
            with self.assertRaises(RuntimeError):
                apply_chat.apply_chat(self.config, text, responses=True)
            self.assertTrue(all(c.args[0] == "get" for c in arm.call_args_list))
            resources[operation_id]["properties"]["urlTemplate"] = "/unexpected"
            arm.reset_mock()
            with self.assertRaises(RuntimeError):
                apply_chat.apply_chat(self.config, text, responses=True)
            self.assertTrue(all(c.args[0] == "get" for c in arm.call_args_list))

    def test_responses_and_legacy_modes_are_mutually_exclusive(self):
        with patch.object(apply_chat, "arm") as arm:
            with self.assertRaises(ValueError):
                apply_chat.apply_chat(self.config, "<policies />", legacy=True, responses=True)
            arm.assert_not_called()

    def test_legacy_stage_only_writes_operation_and_policy_and_preserves_existing(self):
        resources = dict(configure.build_api_operations(self.config))
        api_id = poclib.apim_id(self.config) + "/apis/" + poclib.API_ID
        operation_id = api_id + "/operations/legacy-chat"
        target = operation_id + "/policies/policy"
        pool_id, pool = configure.build_pool(self.config)
        resources[pool_id] = pool
        resources[api_id + "/operations"] = {"value": [
            {"name": path.rsplit("/", 1)[1], **body}
            for path, body in configure.build_api_operations(self.config)[1:]
        ]}
        resources[operation_id + "/policies"] = {"value": []}
        text = configure.policy(
            self.config, "/openai/deployments/YOUR_DEPLOYMENT_NAME/chat/completions", True,
            poclib.POOL_ID, "https://cognitiveservices.azure.com", responses=False)

        def fake_arm(method, resource_id, body=None, **kwargs):
            if method == "put":
                self.assertIn(resource_id, (operation_id, target))
                resources[resource_id] = body
                if resource_id == operation_id:
                    resources[api_id + "/operations"]["value"].append(
                        {"name": "legacy-chat", **body})
                else:
                    resources[operation_id + "/policies"]["value"] = [{"name": "policy"}]
            if method == "get" and resource_id == target:
                self.assertEqual(kwargs, {"query": {"format": "rawxml"}})
            return resources[resource_id]

        with patch.object(apply_chat, "arm", side_effect=fake_arm) as arm:
            apply_chat.apply_chat(self.config, text, legacy=True)
            self.assertEqual([c.args[1] for c in arm.call_args_list if c.args[0] == "put"],
                             [operation_id, target])
            arm.reset_mock()
            apply_chat.apply_chat(self.config, text, legacy=True)
            self.assertTrue(all(c.args[0] == "get" for c in arm.call_args_list))
            resources[target] = {"properties": {"value": "<policies />"}}
            arm.reset_mock()
            with self.assertRaises(RuntimeError):
                apply_chat.apply_chat(self.config, text, legacy=True)
            self.assertTrue(all(c.args[0] == "get" for c in arm.call_args_list))

    def test_legacy_operation_rejects_drift_collision_and_pagination(self):
        api_id = poclib.apim_id(self.config) + "/apis/" + poclib.API_ID
        desired = apply_chat.legacy_operation(self.config)
        foreign = {"properties": {**desired["properties"], "description": "foreign"}}
        for inventory in (
            {"value": [{"name": "legacy-chat", **foreign}]},
            {"value": [{"name": "other", **desired}]},
            {"value": [], "nextLink": "more"},
        ):
            with self.subTest(inventory=inventory):
                with patch.object(apply_chat, "arm", return_value=inventory) as arm:
                    with self.assertRaises(RuntimeError):
                        apply_chat.ensure_legacy_operation(self.config, api_id)
                    self.assertTrue(all(c.args[0] == "get" for c in arm.call_args_list))

    def test_legacy_policy_rejects_wrong_route_version_or_pool_before_azure(self):
        text = configure.policy(
            self.config, "/openai/deployments/YOUR_DEPLOYMENT_NAME/chat/completions", True,
            poclib.POOL_ID, "https://cognitiveservices.azure.com", responses=False)
        for wrong in (
            text.replace("/deployments/YOUR_DEPLOYMENT_NAME/", "/deployments/other/"),
            text.replace("2024-10-21", "2023-01-01"),
            text.replace('backend-id="foundry-pool"', 'backend-id="other"'),
        ):
            with patch.object(apply_chat, "arm") as arm:
                with self.assertRaises(RuntimeError):
                    apply_chat.apply_chat(self.config, wrong, legacy=True)
                arm.assert_not_called()

    def test_trace_metadata_repair_only_replaces_known_expressions(self):
        desired = configure.policy(
            self.config, "/openai/v1/chat/completions", False, poclib.POOL_ID,
            "https://cognitiveservices.azure.com", responses=False)
        root = ElementTree.fromstring(desired)
        for name, header in (("retryAfter", "Retry-After"), ("retryAfterMs", "retry-after-ms")):
            root.find(f".//trace/metadata[@name='{name}']").set(
                "value", f'@(context.Response.Headers.GetValueOrDefault("{header}", ""))')
        old = ElementTree.tostring(root, encoding="unicode")
        self.assertEqual(apply_chat.canonical(apply_chat.repair_retry_trace_metadata(old)),
                         apply_chat.canonical(desired))
        self.assertEqual(apply_chat.canonical(apply_chat.repair_retry_trace_metadata(desired)),
                         apply_chat.canonical(desired))
        for malformed in (old.replace('name="retryAfter"', 'name="other"'),
                          old.replace("Retry-After", "Unexpected-Header")):
            with self.assertRaises(RuntimeError):
                apply_chat.repair_retry_trace_metadata(malformed)

    def test_trace_metadata_apply_rejects_unrelated_drift(self):
        resources = dict(configure.build_api_operations(self.config))
        api_id = poclib.apim_id(self.config) + "/apis/" + poclib.API_ID
        pool_id, pool = configure.build_pool(self.config)
        resources[pool_id] = pool
        target = api_id + "/operations/chat/policies/policy"
        resources[api_id + "/operations/chat/policies"] = {"value": [{"name": "policy"}]}
        desired = configure.policy(
            self.config, "/openai/v1/chat/completions", False, poclib.POOL_ID,
            "https://cognitiveservices.azure.com", responses=False)
        root = ElementTree.fromstring(desired)
        for name, header in (("retryAfter", "Retry-After"), ("retryAfterMs", "retry-after-ms")):
            root.find(f".//trace/metadata[@name='{name}']").set(
                "value", f'@(context.Response.Headers.GetValueOrDefault("{header}", ""))')
        old = ElementTree.tostring(root, encoding="unicode")
        resources[target] = {"properties": {"value": old}}

        def fake_arm(method, resource_id, body=None, **kwargs):
            if method == "put":
                self.assertEqual(resource_id, target)
                resources[resource_id] = body
            return resources[resource_id]

        with patch.object(apply_chat, "arm", side_effect=fake_arm) as arm:
            with self.assertRaises(RuntimeError):
                apply_chat.apply_chat(self.config, desired)
            self.assertTrue(all(c.args[0] == "get" for c in arm.call_args_list))
            arm.reset_mock()
            apply_chat.apply_chat(self.config, desired, fix_trace_metadata=True)
            self.assertEqual([c.args[1] for c in arm.call_args_list if c.args[0] == "put"], [target])
            arm.reset_mock()
            apply_chat.apply_chat(self.config, desired, fix_trace_metadata=True)
            self.assertTrue(all(c.args[0] == "get" for c in arm.call_args_list))
            resources[target] = {"properties": {"value": old.replace('timeout="60"', 'timeout="30"')}}
            arm.reset_mock()
            with self.assertRaises(RuntimeError):
                apply_chat.apply_chat(self.config, desired, fix_trace_metadata=True)
            self.assertTrue(all(c.args[0] == "get" for c in arm.call_args_list))

    def test_store_override_removal_is_exact_and_idempotent(self):
        desired = configure.policy(
            self.config, "/openai/v1/responses", False, poclib.POOL_ID,
            "https://cognitiveservices.azure.com", responses=True)
        current = with_store_override(desired)
        self.assertEqual(apply_chat.canonical(apply_chat.without_store_override(current)),
                         apply_chat.canonical(desired))
        self.assertEqual(apply_chat.canonical(apply_chat.without_store_override(desired)),
                         apply_chat.canonical(desired))
        for unknown in (
            current.replace("false; return", "true; return"),
            current.replace("<set-body>", '<set-body template="liquid">'),
            with_store_override(current),
        ):
            with self.assertRaises(RuntimeError):
                apply_chat.without_store_override(unknown)

    def test_store_override_removal_only_writes_responses_and_rejects_other_drift(self):
        resources = dict(configure.build_api_operations(self.config))
        api_id = poclib.apim_id(self.config) + "/apis/" + poclib.API_ID
        pool_id, pool = configure.build_pool(self.config)
        resources[pool_id] = pool
        target = api_id + "/operations/responses/policies/policy"
        resources[api_id + "/operations/responses/policies"] = {"value": [{"name": "policy"}]}
        desired = configure.policy(
            self.config, "/openai/v1/responses", False, poclib.POOL_ID,
            "https://cognitiveservices.azure.com", responses=True)
        current = with_store_override(desired)
        resources[target] = {"properties": {"value": current}}

        def fake_arm(method, resource_id, body=None, **kwargs):
            if method == "put":
                self.assertEqual(resource_id, target)
                resources[resource_id] = body
            return resources[resource_id]

        with patch.object(apply_chat, "arm", side_effect=fake_arm) as arm:
            with self.assertRaises(RuntimeError):
                apply_chat.apply_chat(self.config, desired, responses=True)
            self.assertTrue(all(c.args[0] == "get" for c in arm.call_args_list))
            arm.reset_mock()
            apply_chat.apply_chat(self.config, desired, responses=True, remove_store_override=True)
            self.assertEqual([c.args[1] for c in arm.call_args_list if c.args[0] == "put"], [target])
            arm.reset_mock()
            apply_chat.apply_chat(self.config, desired, responses=True, remove_store_override=True)
            self.assertTrue(all(c.args[0] == "get" for c in arm.call_args_list))
            resources[target] = {"properties": {"value": current.replace('timeout="60"', 'timeout="30"')}}
            arm.reset_mock()
            with self.assertRaises(RuntimeError):
                apply_chat.apply_chat(self.config, desired, responses=True, remove_store_override=True)
            self.assertTrue(all(c.args[0] == "get" for c in arm.call_args_list))

    def test_store_override_removal_rejects_wrong_mode_and_unmodified_local_xml(self):
        text = configure.policy(
            self.config, "/openai/v1/responses", False, poclib.POOL_ID,
            "https://cognitiveservices.azure.com", responses=True)
        with patch.object(apply_chat, "arm") as arm:
            for mode in ({}, {"legacy": True}):
                with self.assertRaises(ValueError):
                    apply_chat.apply_chat(self.config, text, remove_store_override=True, **mode)
            with self.assertRaises(RuntimeError):
                apply_chat.apply_chat(self.config, with_store_override(text), responses=True,
                                      remove_store_override=True)
            arm.assert_not_called()

    def test_azure_json_accepts_utf8_bom(self):
        result = MagicMock(returncode=0, stdout='\ufeff{"value": []}', stderr="")
        with patch.object(poclib.subprocess, "run", return_value=result):
            self.assertEqual(poclib.az_json(["rest", "--method", "get"]), {"value": []})

    def test_arm_requests_json_for_policy_responses(self):
        with patch.object(poclib, "az_json") as request:
            for method in ("get", "put"):
                poclib.arm(method, "/policy", query={"format": "rawxml"})
                args = request.call_args.args[0]
                self.assertEqual(args.count("--headers"), 1)
                self.assertIn("Accept=application/json", args)
                self.assertEqual("If-Match=*" in args, method == "put")
                self.assertIn("&format=rawxml", args[args.index("--url") + 1])

    def test_requests_restrict_state_and_cost(self):
        schema = configure.request_schema(self.config, True, False)
        props = schema["properties"]
        self.assertEqual(props["store"]["enum"], [False])
        self.assertEqual(props["previous_response_id"]["type"], "null")
        self.assertEqual(props["conversation"]["type"], "null")
        self.assertEqual(props["max_output_tokens"]["maximum"], 128)
        self.assertEqual(props["service_tier"]["enum"], ["default"])
        self.assertEqual(props["tools"]["maxItems"], 0)
        chat = configure.request_schema(self.config, False, False)
        self.assertIn("max_completion_tokens", chat["required"])
        self.assertEqual(chat["properties"]["model"]["enum"], ["YOUR_DEPLOYMENT_NAME"])

    def test_diagnostics_no_bodies_or_secrets(self):
        diagnostic = next(body["properties"] for path, body in self.resources.items()
                          if "/diagnostics/" in path)
        for side in ("frontend", "backend"):
            for direction in ("request", "response"):
                message = diagnostic[side][direction]
                self.assertEqual(message["headers"], [])
                self.assertEqual(message["body"]["bytes"], 0)
                self.assertIn({"value": "subscription-key", "mode": "Hide"},
                              message["dataMasking"]["queryParams"])

    def test_member_identification_never_counts_pool_as_member(self):
        self.assertIsNone(validate.selected_backend(self.config, {
            "x-poc-backend-id": "foundry-pool", "x-poc-backend-host": "apim-test.azure-api.net"}))
        self.assertEqual(validate.selected_backend(self.config, {
            "x-poc-backend-host": "account-two.openai.azure.com"}), 2)
        with self.assertRaises(ValueError):
            validate.selected_backend(self.config, {
                "x-poc-backend-host": "account-two.openai.azure.com", "x-poc-backend-id": "foundry-1"})

    def test_response_completion_and_usage(self):
        usage, _ = validate.analyze_response(
            json.dumps({"object": "response", "status": "completed",
                        "usage": {"input_tokens": 10, "output_tokens": 5, "secret": "discard"}}).encode(),
            True, False)
        self.assertEqual(usage, {"input_tokens": 10, "output_tokens": 5})
        with self.assertRaises(ValueError):
            validate.analyze_response(b'{"object":"response","status":"incomplete"}', True, False)
        with self.assertRaises(ValueError):
            validate.analyze_response(b'{"choices":[{"finish_reason":"length"}]}', False, False)

    def test_sse_terminal_markers(self):
        self.assertEqual(validate.analyze_response(
            b'data: {"choices":[{"finish_reason":"stop"}]}\n\ndata: [DONE]\n\n', False, True)[1], 1)
        with self.assertRaises(ValueError):
            validate.analyze_response(
                b'data: {"choices":[{"finish_reason":"length"}]}\n\ndata: [DONE]\n\n', False, True)
        with self.assertRaises(ValueError):
            validate.analyze_response(b'data: {"type":"response.created"}\n\n', True, True)
        with self.assertRaises(ValueError):
            validate.analyze_response(b'data: {"type":"response.failed"}\n\n', True, True)
        self.assertEqual(validate.analyze_response(
            b'data: {"type":"response.completed","response":{"usage":{"output_tokens":1}}}\n\n',
            True, True)[0], {"output_tokens": 1})

    def test_gateway_secret_destination_pinned(self):
        self.assertEqual(poclib.gateway_host(self.config, {
            "properties": {"gatewayUrl": "https://apim-test.azure-api.net"}}), "apim-test.azure-api.net")
        for url in ("http://apim-test.azure-api.net", "https://attacker.example",
                    "https://apim-test.azure-api.net:444"):
            with self.assertRaises(RuntimeError):
                poclib.gateway_host(self.config, {"properties": {"gatewayUrl": url}})

    def test_azure_payload_uses_stdin_not_command_arguments(self):
        fake = type("Result", (), {"returncode": 0, "stdout": "{}", "stderr": ""})()
        with patch("poclib.subprocess.run", return_value=fake) as run:
            poclib.arm("put", "/test", {"secret": "not-on-command-line"})
        args, kwargs = run.call_args
        self.assertNotIn("not-on-command-line", " ".join(args[0]))
        self.assertIn("@/dev/stdin", args[0])
        self.assertEqual(json.loads(kwargs["input"]), {"secret": "not-on-command-line"})

    def test_total_deadline_interrupts_blocking_work(self):
        started = time.monotonic()
        with self.assertRaises(TimeoutError):
            with validate.total_deadline(0.02):
                time.sleep(1)
        self.assertLess(time.monotonic() - started, 0.5)

    def test_budget_blocks_before_network(self):
        with patch.object(validate, "reserved_attempts", return_value=100), \
                patch.object(validate.http.client, "HTTPSConnection") as connection:
            with self.assertRaises(RuntimeError):
                validate.call_gateway(self.config, "apim-test.azure-api.net", "secret-key",
                                      "/v1/responses", validate.payload(self.config, True))
            connection.assert_not_called()

    def test_invalid_response_body_and_key_are_not_logged(self):
        response = MagicMock()
        response.status = 200
        response.getheader.side_effect = lambda name, default=None: {
            "x-poc-attempts": "1", "x-poc-backend-host": "account-one.openai.azure.com",
        }.get(name, default)
        response.read1.side_effect = [b"secret-response-not-json", b""]
        connection = MagicMock()
        connection.getresponse.return_value = response
        with patch.object(validate, "reserved_attempts", return_value=0), \
                patch.object(validate, "save_event") as save, \
                patch.object(validate.http.client, "HTTPSConnection", return_value=connection), \
                patch("builtins.print") as output:
            result = validate.call_gateway(self.config, "apim-test.azure-api.net", "secret-key",
                                           "/v1/responses", validate.payload(self.config, True))
        self.assertFalse(result["passed"])
        combined = str(save.call_args_list) + str(output.call_args_list)
        self.assertNotIn("secret-response", combined)
        self.assertNotIn("secret-key", combined)


if __name__ == "__main__":
    unittest.main()
