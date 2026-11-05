from pathlib import Path
import re
import unittest
from uuid import UUID


ROOT = Path(__file__).resolve().parents[1]
ONTOLOGY = ROOT / "fabric" / "ontology"


class OntologyTests(unittest.TestCase):
    def test_native_source_lineages_remain_stable_for_updates(self) -> None:
        seen: set[UUID] = set()
        for path in [*sorted((ONTOLOGY / "tables").glob("*.tmdl")), ONTOLOGY / "expressions.tmdl"]:
            text = path.read_text()
            tags = re.findall(r"^\s+lineageTag: ([\w-]+)$", text, re.MULTILINE)
            expected = 1 + len(re.findall(r"^\tcolumn ", text, re.MULTILINE))
            self.assertEqual(len(tags), expected, path.name)
            for tag in tags:
                identifier = UUID(tag)
                self.assertNotIn(identifier, seen, path.name)
                seen.add(identifier)

    def test_model_references_exactly_the_checked_in_entities_and_tables(self) -> None:
        model = (ONTOLOGY / "model.tmdl").read_text()
        for kind, directory in [("entity", "entities"), ("table", "tables")]:
            expected = {path.stem for path in (ONTOLOGY / directory).glob("*.tmdl")}
            actual = set(re.findall(rf"ref {kind} (\w+)", model))
            self.assertEqual(actual, expected)
            self.assertEqual(len(actual), 5)

    def test_every_property_has_a_real_reporting_column_binding(self) -> None:
        schema = (ROOT / "fabric" / "warehouse" / "001_analytics_schema.sql").read_text()
        for path in (ONTOLOGY / "entities").glob("*.tmdl"):
            text = path.read_text()
            table_match = re.search(r"backingTable: (\w+)", text)
            key_match = re.search(r"keyProperty: (\w+)", text)
            assert table_match is not None, path.name
            assert key_match is not None, path.name
            table = table_match.group(1)
            key = key_match.group(1)
            backing = (ONTOLOGY / "tables" / f"{table}.tmdl").read_text()
            self.assertIn("schemaName: reporting", backing)
            physical_match = re.search(rf"CREATE TABLE reporting\.{table}\s*\(([^;]+)\);", schema)
            assert physical_match is not None, table
            physical = physical_match.group(1)
            properties = re.findall(r"^\tproperty (\w+)", text, re.MULTILINE)
            bindings = re.findall(r"valueColumn: (\w+)\.(\w+)", text)
            self.assertEqual(len(properties), len(bindings), path.name)
            self.assertIn(key, properties)
            for bound_table, column in bindings:
                self.assertEqual(bound_table, table)
                self.assertRegex(backing, rf"\bcolumn {column}\b")
                self.assertRegex(physical, rf"\b{column}\s")

    def test_entity_relationships_use_real_native_relationships(self) -> None:
        entity_relationships = (ONTOLOGY / "entityRelationships.tmdl").read_text()
        native = (ONTOLOGY / "relationships.tmdl").read_text()
        bindings = re.findall(r"relationship: (\w+)", entity_relationships)
        declared = re.findall(r"^relationship (\w+)", native, re.MULTILINE)
        self.assertEqual(set(bindings), set(declared))
        self.assertEqual(len(bindings), 4)
        for table, column in re.findall(r"(?:fromColumn|toColumn): (\w+)\.(\w+)", native):
            self.assertRegex((ONTOLOGY / "tables" / f"{table}.tmdl").read_text(), rf"\bcolumn {column}\b")

    def test_ontology_has_no_person_level_table_or_invented_source_fields(self) -> None:
        for path in (ONTOLOGY / "tables").glob("*.tmdl"):
            text = path.read_text()
            self.assertNotIn("ClientId", text)
            self.assertNotIn("AppointmentId", text)
            self.assertNotIn("ReferralId", text)
            self.assertNotIn("PreferredLanguage", text)
            self.assertNotIn("analytics.", text)


if __name__ == "__main__":
    unittest.main()
