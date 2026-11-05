from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import time
from pathlib import Path

import pyodbc

SQL_COPT_SS_ACCESS_TOKEN = 1256


def get_access_token(tenant_id: str | None = None) -> str:
    azure_cli = shutil.which("az") or shutil.which("az.cmd")
    if azure_cli is None:
        raise RuntimeError("Azure CLI executable was not found")
    arguments = [
        azure_cli,
        "account",
        "get-access-token",
        "--resource",
        "https://database.windows.net",
        "--query",
        "accessToken",
        "--output",
        "tsv",
    ]
    if tenant_id:
        arguments.extend(["--tenant", tenant_id])
    result = subprocess.run(
        arguments,
        check=True,
        capture_output=True,
        text=True,
        timeout=60,
    )
    token = result.stdout.strip()
    if not token:
        raise RuntimeError("Azure CLI returned an empty SQL access token")
    return token


def encode_access_token(token: str) -> bytes:
    encoded = token.encode("utf-16-le")
    return len(encoded).to_bytes(4, "little") + encoded


def execute_batches(cursor: pyodbc.Cursor, sql: str) -> tuple[int, list[dict[str, object]]]:
    executed = 0
    results: list[dict[str, object]] = []
    for batch in re.split(r"(?im)^\s*GO\s*$", sql):
        if not batch.strip():
            continue
        cursor.execute(batch)
        executed += 1
        while True:
            if cursor.description:
                columns = [column[0] for column in cursor.description]
                results.append(
                    {"columns": columns, "rows": [list(row) for row in cursor.fetchall()]}
                )
            # SQL errors after a SELECT can surface only when advancing result sets.
            if not cursor.nextset():
                break
    return executed, results


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--server", required=True)
    parser.add_argument("--database", required=True)
    parser.add_argument("--tenant-id")
    parser.add_argument("files", nargs="+", type=Path)
    args = parser.parse_args()

    token = get_access_token(args.tenant_id)
    connection = None
    for attempt in range(4):
        try:
            connection = pyodbc.connect(
                (
                    "Driver={ODBC Driver 18 for SQL Server};"
                    f"Server=tcp:{args.server},1433;"
                    f"Database={args.database};"
                    "Encrypt=yes;TrustServerCertificate=no;Connection Timeout=30;"
                ),
                attrs_before={SQL_COPT_SS_ACCESS_TOKEN: encode_access_token(token)},
                autocommit=True,
            )
            break
        except pyodbc.OperationalError as exc:
            if attempt == 3 or not exc.args or exc.args[0] not in {"08001", "08S01", "HYT00", "HYT01"}:
                raise
            time.sleep(10 * (attempt + 1))
    assert connection is not None
    token = ""

    executed = 0
    results: list[dict[str, object]] = []
    try:
        connection.timeout = 120
        cursor = connection.cursor()
        for path in args.files:
            sql = path.read_text(encoding="utf-8")
            batch_count, file_results = execute_batches(cursor, sql)
            executed += batch_count
            results.extend(file_results)
    finally:
        connection.close()

    print(json.dumps({"status": "Succeeded", "batchesExecuted": executed, "results": results}, default=str))


if __name__ == "__main__":
    main()
