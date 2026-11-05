import importlib.util
import json
from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "fabric_data_agent_runner", ROOT / "scripts" / "Invoke-FabricDataAgent.py"
)
assert SPEC is not None and SPEC.loader is not None
RUNNER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(RUNNER)


class DataAgentTests(unittest.TestCase):
    def test_native_warehouse_pipeline_requires_no_stored_credential(self) -> None:
        definition = json.loads(
            (ROOT / "fabric" / "pipeline" / "pipeline-content.template.json").read_text()
        )
        activity = definition["properties"]["activities"][0]
        self.assertNotIn("externalReferences", activity)
        linked_service = activity["linkedService"]["properties"]
        self.assertEqual(linked_service["type"], "DataWarehouse")
        self.assertEqual(
            set(linked_service["typeProperties"]),
            {"endpoint", "artifactId", "workspaceId"},
        )

    def test_model_explains_upstream_suppression_to_query_generation(self) -> None:
        definition = (
            ROOT / "fabric" / "semantic-model" / "definition" / "tables"
            / "CommunityHealthAccess.tmdl"
        ).read_text()
        self.assertTrue(definition.startswith("/// Synthetic appointment reporting aggregates."))
        self.assertIn("/// upstream data removal", definition)
        self.assertIn("/// fewer than 11 appointments.", definition)

    def test_discovers_the_actual_question_argument(self) -> None:
        self.assertEqual(
            RUNNER.get_question_argument(
                {"properties": {"userQuestion": {"type": "string"}}}
            ),
            "userQuestion",
        )

    def test_rejects_ambiguous_or_nontext_tool_arguments(self) -> None:
        for properties in (
            {},
            {"question": {"type": "string"}, "other": {"type": "string"}},
            {"question": {"type": "integer"}},
        ):
            with self.assertRaises(ValueError):
                RUNNER.get_question_argument({"properties": properties})

    def test_selected_tables_match_semantic_model_lineage_tags(self) -> None:
        source = json.loads(
            (ROOT / "fabric" / "data-agent" / "datasource.template.json").read_text()
        )
        selected = {
            element["display_name"]: element
            for element in source["elements"]
            if element["is_selected"]
        }
        tables = ROOT / "fabric" / "semantic-model" / "definition" / "tables"
        self.assertEqual(set(selected), {path.stem for path in tables.glob("*.tmdl")})
        self.assertEqual(len(selected), 3)
        for name, element in selected.items():
            definition = (tables / f"{name}.tmdl").read_text()
            lineage = re.search(r"^\tlineageTag: ([\w-]+)$", definition, re.MULTILINE)
            assert lineage is not None, name
            self.assertEqual(element["id"], lineage.group(1))
            self.assertEqual(element["type"], "semantic_model.table")


if __name__ == "__main__":
    unittest.main()
