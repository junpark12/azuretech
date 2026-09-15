"""REFERENCE ONLY: sanitized original tests; not runnable standalone.

Requires companion test_gateway.py plus original monitoring/poclib/configuration
helpers and templates, which are not provided. Set POC_SOURCE_ROOT to a separately
reviewed compatible project. No cloud execution is claimed. Test resource names
are synthetic and the instrumentation-key value is a nonfunctional placeholder.
Never supply production connection strings or credentials to these fixtures.
"""
import copy
import unittest
from unittest.mock import patch

from test_gateway import configure
import monitoring
from poclib import apim_id


class MonitoringTests(unittest.TestCase):
    def setUp(self):
        self.config = {"subscriptionId": "test-sub", "resourceGroup": "test-rg",
                       "apimName": "apim-test", "ownershipTag": "test-owner",
                       "deploymentName": "test-model", "accountNames": ["one", "two"]}
        self.base = apim_id(self.config)
        self.appi = "/subscriptions/test-sub/resourceGroups/test-rg/providers/Microsoft.Insights/components/test"
        self.connection = "InstrumentationKey=YOUR_TEST_INSTRUMENTATION_KEY"

    def test_diagnostic_metadata_only_and_shared(self):
        resource_id, body = monitoring.diagnostic_definition(self.config)
        self.assertEqual(resource_id, self.base + "/apis/llm-gateway/diagnostics/applicationinsights")
        self.assertEqual(dict(configure.build_resources(
            self.config, "https://cognitiveservices.azure.com"))[resource_id], body)
        props = body["properties"]
        self.assertEqual(props["sampling"]["percentage"], 100)
        self.assertFalse(props["logClientIp"])
        self.assertFalse(props["metrics"])
        self.assertEqual(props["verbosity"], "information")
        normalized = copy.deepcopy(body)
        normalized["properties"]["metrics"] = None
        self.assertTrue(monitoring.diagnostic_matches(body, normalized))
        normalized["properties"]["metrics"] = True
        self.assertFalse(monitoring.diagnostic_matches(body, normalized))
        for side in ("frontend", "backend"):
            for message in ("request", "response"):
                settings = props[side][message]
                self.assertEqual(settings["body"]["bytes"], 0)
                self.assertEqual(settings["headers"], [])
                self.assertTrue(all(item["mode"] == "Mask"
                                    for item in settings["dataMasking"]["headers"]))
                self.assertIn({"value": "subscription-key", "mode": "Hide"},
                              settings["dataMasking"]["queryParams"])

    def test_only_two_writes_and_idempotence(self):
        saved = {}

        def fake_arm(method, path, body=None, **kwargs):
            self.assertEqual(kwargs["sensitive"], not (method == "put" and "/diagnostics/" in path))
            if method == "put":
                self.assertIn(path, (self.base + "/loggers/poc-appinsights",
                                    self.base + "/apis/llm-gateway/diagnostics/applicationinsights"))
                saved[path] = {"name": path.rsplit("/", 1)[1], **copy.deepcopy(body)}
                return saved[path]
            if path.endswith(("/loggers", "/diagnostics")):
                return {"value": [v for k, v in saved.items() if k.rsplit("/", 1)[0] == path]}
            return saved[path]

        with patch.object(monitoring, "arm", side_effect=fake_arm) as mock:
            monitoring.apply_monitoring(self.config, self.appi, self.connection)
            self.assertEqual(sum(c.args[0] == "put" for c in mock.call_args_list), 2)
            logger = saved[self.base + "/loggers/poc-appinsights"]["properties"]
            self.assertEqual(logger["credentials"]["identityClientId"], "SystemAssigned")
            self.assertEqual(logger["resourceId"], self.appi)
            mock.reset_mock()
            monitoring.apply_monitoring(self.config, self.appi, self.connection)
            self.assertFalse(any(c.args[0] == "put" for c in mock.call_args_list))

    def test_drift_or_pagination_prevents_all_writes(self):
        for bad_scope in ("loggers", "diagnostics", "pagination"):
            def fake_arm(method, path, body=None, **kwargs):
                self.assertEqual(method, "get")
                if bad_scope == "pagination":
                    return {"value": [], "nextLink": "next-page"}
                if path.endswith("/" + bad_scope):
                    return {"value": [{"name": "poc-appinsights" if bad_scope == "loggers"
                                       else "applicationinsights", "properties": {}}]}
                return {"value": []}

            with self.subTest(scope=bad_scope), patch.object(monitoring, "arm", side_effect=fake_arm):
                with self.assertRaises(RuntimeError):
                    monitoring.apply_monitoring(self.config, self.appi, self.connection)

    def test_invalid_connection_makes_no_calls(self):
        with patch.object(monitoring, "arm") as mock:
            with self.assertRaises(ValueError):
                monitoring.apply_monitoring(self.config, self.appi, "")
            mock.assert_not_called()

    def test_server_named_values_resolved_without_overwrite(self):
        desired = {"properties": {"description": "test-owner", "credentials": {
            "connectionString": self.connection, "identityClientId": "SystemAssigned"}}}
        actual = copy.deepcopy(desired)
        actual["properties"]["credentials"]["identityClientId"] = "{{identity-ref}}"
        named_id = self.base + "/namedValues/identity-id"

        def fake_arm(method, path, **kwargs):
            self.assertTrue(kwargs["sensitive"])
            if method == "get" and path == self.base + "/namedValues":
                return {"value": [{"name": "identity-id", "id": named_id,
                                   "properties": {"displayName": "identity-ref"}}]}
            self.assertEqual((method, path), ("post", named_id + "/listValue"))
            return {"value": "SystemAssigned"}

        with patch.object(monitoring, "arm", side_effect=fake_arm):
            self.assertTrue(monitoring.logger_matches(desired, actual, self.base))
        self.assertEqual(actual["properties"]["credentials"]["identityClientId"], "{{identity-ref}}")
        actual["properties"]["credentials"]["identityClientId"] = "{{identity-id}}"
        with patch.object(monitoring, "arm", side_effect=fake_arm):
            self.assertTrue(monitoring.logger_matches(desired, actual, self.base))
        with patch.object(monitoring, "arm") as mock:
            actual["properties"]["description"] = "foreign-owner"
            self.assertFalse(monitoring.logger_matches(desired, actual, self.base))
            mock.assert_not_called()

    def test_retention_only_known_default_tables_and_idempotence(self):
        workspace = "/subscriptions/test/resourceGroups/test/providers/Microsoft.OperationalInsights/workspaces/test"
        saved = {f"{workspace}/tables/{name}": {"properties": {
            "schema": {"name": name}, "plan": "Analytics",
            "retentionInDays": 90, "totalRetentionInDays": 90,
            "retentionInDaysAsDefault": True}} for name in monitoring.TABLES}

        def fake_arm(method, path, body=None, **kwargs):
            self.assertIn(path, saved)
            self.assertEqual(kwargs["version"], "2022-10-01")
            if method == "patch":
                self.assertEqual(body, {"properties": {"retentionInDays": 30, "totalRetentionInDays": 30}})
                saved[path]["properties"].update(body["properties"])
            else:
                self.assertEqual(method, "get")
            return saved[path]

        with patch.object(monitoring, "arm", side_effect=fake_arm) as mock:
            monitoring.apply_retention(workspace)
            self.assertEqual(sum(c.args[0] == "patch" for c in mock.call_args_list), 4)
            mock.reset_mock()
            monitoring.apply_retention(workspace)
            self.assertFalse(any(c.args[0] == "patch" for c in mock.call_args_list))
            saved[next(iter(saved))]["properties"]["retentionInDays"] = 60
            mock.reset_mock()
            with self.assertRaises(RuntimeError):
                monitoring.apply_retention(workspace)
            self.assertFalse(any(c.args[0] == "patch" for c in mock.call_args_list))
