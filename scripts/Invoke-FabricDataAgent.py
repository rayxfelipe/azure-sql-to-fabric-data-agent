from __future__ import annotations

import argparse
import asyncio
from datetime import datetime, timedelta, timezone
import json
from pathlib import Path
import shutil
import subprocess
import time
from uuid import UUID


def get_access_token(tenant_id: UUID) -> str:
    azure_cli = shutil.which("az") or shutil.which("az.cmd")
    if azure_cli is None:
        raise RuntimeError("Azure CLI executable was not found")
    result = subprocess.run(
        [
            azure_cli,
            "account",
            "get-access-token",
            "--tenant",
            str(tenant_id),
            "--resource",
            "https://api.fabric.microsoft.com",
            "--query",
            "accessToken",
            "--output",
            "tsv",
        ],
        capture_output=True,
        text=True,
        check=True,
        timeout=60,
    )
    token = result.stdout.strip()
    if not token:
        raise RuntimeError("Azure CLI returned an empty Fabric access token")
    return token


def get_question_argument(schema: dict[str, object]) -> str:
    properties = schema.get("properties")
    if not isinstance(properties, dict) or len(properties) != 1:
        raise ValueError("Expected exactly one question argument in the agent tool")
    name, definition = next(iter(properties.items()))
    if not isinstance(definition, dict) or definition.get("type") != "string":
        raise ValueError("Expected a string question argument in the agent tool")
    return name


async def query_agent(
    url: str, token: str, question: str, timeout_seconds: int
) -> dict[str, object]:
    from mcp import ClientSession
    from mcp.client.streamable_http import streamablehttp_client

    async with asyncio.timeout(timeout_seconds + 30):
        async with streamablehttp_client(
            url,
            headers={"Authorization": f"Bearer {token}"},
            timeout=30,
            sse_read_timeout=timeout_seconds,
        ) as (read, write, _):
            async with ClientSession(read, write) as session:
                await session.initialize()
                tools = (await session.list_tools()).tools
                if len(tools) != 1:
                    raise RuntimeError("Expected exactly one Fabric data-agent tool")
                tool = tools[0]
                argument = get_question_argument(tool.inputSchema)
                result = await session.call_tool(
                    tool.name,
                    {argument: question},
                    read_timeout_seconds=timedelta(seconds=timeout_seconds),
                )
                answer = "\n".join(
                    block.text for block in result.content if block.type == "text"
                )
                if not answer.strip():
                    raise RuntimeError("The data agent returned no text answer")
                return {
                    "tool": tool.name,
                    "answer": answer,
                    "isError": result.isError,
                }


def main() -> None:
    parser = argparse.ArgumentParser(description="Query a published Fabric data agent.")
    parser.add_argument("--workspace-id", required=True, type=UUID)
    parser.add_argument("--data-agent-id", required=True, type=UUID)
    parser.add_argument(
        "--tenant-id", type=UUID, default=UUID("aa56606c-b0ba-43a8-9c11-eb0144a67efb")
    )
    parser.add_argument("--question", required=True)
    parser.add_argument("--timeout-seconds", type=int, default=120)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    if not 1 <= args.timeout_seconds <= 600:
        parser.error("--timeout-seconds must be between 1 and 600")
    if not args.question.strip():
        parser.error("--question must not be empty")

    token = get_access_token(args.tenant_id)
    url = (
        "https://api.fabric.microsoft.com/v1/mcp/workspaces/"
        f"{args.workspace_id}/dataagents/{args.data_agent_id}/agent"
    )
    started = time.monotonic()
    result = asyncio.run(query_agent(url, token, args.question, args.timeout_seconds))
    record = {
        "checkedAt": datetime.now(timezone.utc).isoformat(),
        "workspaceId": str(args.workspace_id),
        "dataAgentId": str(args.data_agent_id),
        "question": args.question,
        "elapsedSeconds": round(time.monotonic() - started, 3),
        **result,
    }
    rendered = json.dumps(record, indent=2)
    if args.output:
        args.output.write_text(rendered + "\n", encoding="utf-8")
    print(rendered, flush=True)
    if result["isError"]:
        raise RuntimeError(f"The published data agent returned an error: {result['answer']}")


if __name__ == "__main__":
    main()
