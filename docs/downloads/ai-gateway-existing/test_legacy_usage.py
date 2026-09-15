"""REFERENCE ONLY: sanitized original tests; not runnable standalone.

Requires companion test_gateway.py and the unprovided original configure,
apply-chat-policy, legacy_usage, and poclib helpers, configuration and templates.
POC_SOURCE_ROOT must identify a separately reviewed compatible original project.
No cloud execution is claimed. IDs/deployments are placeholders; mock fixture
names are synthetic. Never substitute production credentials into these tests.
"""
import copy
import unittest
from unittest.mock import patch
from xml.etree import ElementTree as ET

from test_gateway import configure, apply_chat
from legacy_usage import add_token_usage
from poclib import API_ID, POOL_ID, apim_id


def without_usage(text):
    root = ET.fromstring(text)
    retry = root.find("backend/retry")
    retry.remove(retry.find("choose[@id='legacy-token-usage']"))
    return ET.tostring(root, encoding="unicode")


class LegacyUsageTests(unittest.TestCase):
    def setUp(self):
        self.config = {
            "subscriptionId": "YOUR_SUBSCRIPTION_ID",
            "resourceGroup": "YOUR_RESOURCE_GROUP", "apimName": "apim-test",
            "accountNames": ["account-one", "account-two"],
            "deploymentName": "YOUR_DEPLOYMENT_NAME", "ownershipTag": "test-owner",
        }
        self.text = configure.policy(
            self.config, "/openai/deployments/YOUR_DEPLOYMENT_NAME/chat/completions", True,
            POOL_ID, "https://cognitiveservices.azure.com", responses=False)
        self.old = without_usage(self.text)

    def test_only_legacy_has_usage_trace_and_other_behavior_is_preserved(self):
        for op, _, path, responses, legacy, backend in configure.operations(self.config):
            text = configure.policy(self.config, path, legacy, backend,
                                    "https://cognitiveservices.azure.com", responses=responses)
            root = ET.fromstring(text)
            self.assertEqual(len(root.findall(".//trace/message[.='llm-usage']")),
                             1 if op == "legacy-chat" else 0)
        root = ET.fromstring(self.text)
        retry = root.find("backend/retry")
        self.assertEqual(retry[-2].findtext("message"), "backend-attempt")
        self.assertEqual(retry[-1].get("id"), "legacy-token-usage")
        self.assertEqual(retry.get("count"), "1")
        self.assertEqual(retry.find("forward-request").get("buffer-response"), "false")
        self.assertEqual(root.findall(".//set-body"), [])
        self.assertEqual(apply_chat.canonical(add_token_usage(self.old)),
                         apply_chat.canonical(self.text))
        self.assertEqual(add_token_usage(self.text), self.text)

    def test_usage_is_json_success_only_with_no_secret_or_body_metadata(self):
        root = ET.fromstring(self.text)
        when = root.find("backend/retry/choose/when")
        self.assertIn("StatusCode == 200", when.get("condition"))
        self.assertIn('StartsWith("application/json"', when.get("condition"))
        expression = when.find("set-variable").get("value")
        self.assertIn("As<JObject>(preserveContent: true)", expression)
        for field in ("prompt_tokens", "input_tokens", "completion_tokens",
                      "output_tokens", "total_tokens", "not-reported"):
            self.assertIn(field, expression)
        self.assertEqual(expression.count("Type == JTokenType.Integer"), 3)
        trace = when.find("trace")
        fields = {m.get("name"): m.get("value") for m in trace.findall("metadata")}
        self.assertEqual(set(fields), {"requestId", "subscriptionId", "backendHost", "attempt", "usage"})
        self.assertIn("context.Subscription.Id", fields["subscriptionId"])
        self.assertIn("context.Request.Url.Host", fields["backendHost"])
        for expr in fields.values():
            for forbidden in ("PrimaryKey", "SecondaryKey", "Subscription.Key", ".Body", ".Headers"):
                self.assertNotIn(forbidden, expr)

    def test_malformed_duplicate_or_misplaced_blocks_are_rejected(self):
        wrong = self.text.replace("inputTokens", "otherTokens")
        with self.assertRaises(RuntimeError):
            add_token_usage(wrong)
        root = ET.fromstring(self.text)
        retry = root.find("backend/retry")
        block = retry[-1]
        retry.append(copy.deepcopy(block))
        with self.assertRaises(RuntimeError):
            add_token_usage(ET.tostring(root, encoding="unicode"))
        retry.remove(retry[-1])
        retry.remove(block)
        root.find("outbound").append(block)
        with self.assertRaises(RuntimeError):
            add_token_usage(ET.tostring(root, encoding="unicode"))

    def test_rollout_writes_only_existing_legacy_policy_and_rejects_drift(self):
        resources = dict(configure.build_api_operations(self.config))
        api = apim_id(self.config) + "/apis/" + API_ID
        operation = api + "/operations/legacy-chat"
        target = operation + "/policies/policy"
        legacy = apply_chat.legacy_operation(self.config)
        resources.update({
            operation: legacy,
            api + "/operations": {"value": [{"name": "legacy-chat", **legacy}]},
            operation + "/policies": {"value": [{"name": "policy"}]},
            target: {"properties": {"value": self.old}},
        })
        pool_id, pool = configure.build_pool(self.config)
        resources[pool_id] = pool

        def fake_arm(method, path, body=None, **kwargs):
            if method == "put":
                self.assertEqual(path, target)
                resources[path] = body
            return resources[path]

        with patch.object(apply_chat, "arm", side_effect=fake_arm) as mock:
            with self.assertRaises(RuntimeError):
                apply_chat.apply_chat(self.config, self.text, legacy=True)
            self.assertFalse(any(c.args[0] == "put" for c in mock.call_args_list))
            mock.reset_mock()
            apply_chat.apply_chat(self.config, self.text, legacy=True, add_usage_trace=True)
            self.assertEqual([c.args[1] for c in mock.call_args_list if c.args[0] == "put"], [target])
            mock.reset_mock()
            apply_chat.apply_chat(self.config, self.text, legacy=True, add_usage_trace=True)
            self.assertFalse(any(c.args[0] == "put" for c in mock.call_args_list))
            resources[target] = {"properties": {"value": self.old.replace('timeout="60"', 'timeout="30"')}}
            mock.reset_mock()
            with self.assertRaises(RuntimeError):
                apply_chat.apply_chat(self.config, self.text, legacy=True, add_usage_trace=True)
            self.assertFalse(any(c.args[0] == "put" for c in mock.call_args_list))
            resources[api + "/operations"] = {"value": []}
            mock.reset_mock()
            with self.assertRaises(RuntimeError):
                apply_chat.apply_chat(self.config, self.text, legacy=True, add_usage_trace=True)
            self.assertFalse(any(c.args[0] == "put" for c in mock.call_args_list))

    def test_wrong_mode_or_unmodified_local_policy_makes_no_azure_calls(self):
        with patch.object(apply_chat, "arm") as mock:
            for mode in ({}, {"responses": True}):
                with self.assertRaises(ValueError):
                    apply_chat.apply_chat(self.config, self.text, add_usage_trace=True, **mode)
            with self.assertRaises(RuntimeError):
                apply_chat.apply_chat(self.config, self.old, legacy=True, add_usage_trace=True)
            mock.assert_not_called()
