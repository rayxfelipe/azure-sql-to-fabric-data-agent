import importlib.util
import json
from pathlib import Path
import sys
import unittest
from unittest.mock import MagicMock, patch


PATH = Path(__file__).resolve().parents[1] / "scripts" / "Invoke-SqlWithAccessToken.py"
SPEC = importlib.util.spec_from_file_location("sql_runner", PATH)
assert SPEC is not None and SPEC.loader is not None
SQL_RUNNER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(SQL_RUNNER)


class SqlRunnerTests(unittest.TestCase):
    def test_token_encoding_uses_utf16_byte_length(self) -> None:
        token = "test-\u00e9"
        encoded = SQL_RUNNER.encode_access_token(token)
        self.assertEqual(int.from_bytes(encoded[:4], "little"), len(token.encode("utf-16-le")))
        self.assertEqual(encoded[4:].decode("utf-16-le"), token)

    def test_every_result_set_is_consumed(self) -> None:
        cursor = MagicMock()
        cursor.description = [("value",)]
        cursor.fetchall.side_effect = [[(1,)], [(2,)]]
        cursor.nextset.side_effect = [True, False]
        count, results = SQL_RUNNER.execute_batches(cursor, "SELECT 1; SELECT 2;")
        self.assertEqual(count, 1)
        self.assertEqual([result["rows"] for result in results], [[[1]], [[2]]])

    def test_deferred_sql_error_cannot_be_reported_as_success(self) -> None:
        cursor = MagicMock()
        cursor.description = [("value",)]
        cursor.fetchall.return_value = [(1,)]
        cursor.nextset.side_effect = RuntimeError("SQL validation THROW after SELECT")
        with self.assertRaisesRegex(RuntimeError, "validation THROW"):
            SQL_RUNNER.execute_batches(cursor, "SELECT 1; THROW 51000, 'bad', 1;")

    def test_go_batches_and_empty_batches(self) -> None:
        cursor = MagicMock()
        cursor.description = None
        cursor.nextset.return_value = False
        count, results = SQL_RUNNER.execute_batches(cursor, "GO\nSELECT 1;\nGO\n\nGO\nSELECT 2;\n")
        self.assertEqual(count, 2)
        self.assertEqual(cursor.execute.call_count, 2)
        self.assertEqual(results, [])

    def test_command_sets_timeout_on_connection_not_cursor(self) -> None:
        connection = MagicMock(spec_set=SQL_RUNNER.pyodbc.Connection)
        cursor = MagicMock(spec_set=SQL_RUNNER.pyodbc.Cursor)
        cursor.description = None
        cursor.nextset.return_value = False
        connection.cursor.return_value = cursor
        sql_path = PATH.parent.parent / "database" / "seed" / "003_demo_pulse.sql"
        arguments = ["sql_runner", "--server", "demo", "--database", "demo", str(sql_path)]
        with (
            patch.object(sys, "argv", arguments),
            patch.object(SQL_RUNNER, "get_access_token", return_value="test-token"),
            patch.object(SQL_RUNNER.pyodbc, "connect", return_value=connection),
            patch("builtins.print") as output,
        ):
            SQL_RUNNER.main()
        self.assertEqual(connection.timeout, 120)
        connection.close.assert_called_once()
        self.assertEqual(json.loads(output.call_args.args[0])["status"], "Succeeded")


if __name__ == "__main__":
    unittest.main()
