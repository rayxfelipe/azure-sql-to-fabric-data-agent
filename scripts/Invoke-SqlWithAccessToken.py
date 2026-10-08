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


def get_access_token() -> str:
    azure_cli = shutil.which("az") or shutil.which("az.cmd")
    if azure_cli is None:
        raise RuntimeError("Azure CLI executable was not found")
    result = subprocess.run(
        [
            azure_cli,
            "account",
            "get-access-token",
            "--resource",
            "https://database.windows.net",
            "--query",
            "accessToken",
            "--output",
            "tsv",
        ],
        check=True,
        capture_output=True,
        text=True,
    )
    return result.stdout.strip()


def encode_access_token(token: str) -> bytes:
    encoded = token.encode("utf-16-le")
    return len(encoded).to_bytes(4, "little") + encoded


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--server", required=True)
    parser.add_argument("--database", required=True)
    parser.add_argument("files", nargs="+", type=Path)
    args = parser.parse_args()

    token = get_access_token()
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
        except pyodbc.OperationalError:
            if attempt == 3:
                raise
            time.sleep(10 * (attempt + 1))
    assert connection is not None
    token = ""

    executed = 0
    try:
        cursor = connection.cursor()
        for path in args.files:
            sql = path.read_text(encoding="utf-8")
            for batch in re.split(r"(?im)^\s*GO\s*$", sql):
                if batch.strip():
                    cursor.execute(batch)
                    executed += 1
    finally:
        connection.close()

    print(json.dumps({"status": "Succeeded", "batchesExecuted": executed}))


if __name__ == "__main__":
    main()
