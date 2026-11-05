from datetime import date
import json
import unittest
from unittest.mock import patch

from src.community_health.generator import generate_dataset
from src.community_health.main import app, repository


class ApiTests(unittest.IsolatedAsyncioTestCase):
    async def request(self, path: str) -> tuple[int, bytes]:
        messages = []

        async def receive():
            return {"type": "http.request", "body": b"", "more_body": False}

        async def send(message):
            messages.append(message)

        scope = {
            "type": "http", "asgi": {"version": "3.0"}, "http_version": "1.1",
            "method": "GET", "scheme": "http", "path": path, "raw_path": path.encode(),
            "root_path": "", "query_string": b"", "headers": [],
            "server": ("localtest", 80), "client": ("127.0.0.1", 12345),
        }
        await app(scope, receive, send)
        status = next(message["status"] for message in messages if message["type"] == "http.response.start")
        body = b"".join(message.get("body", b"") for message in messages if message["type"] == "http.response.body")
        return status, body

    async def test_existing_routes_remain_available(self) -> None:
        for path in ("/healthz", "/readyz", "/api/v1/synthetic-data", "/openapi.json", "/docs"):
            with self.subTest(path=path):
                status, body = await self.request(path)
                self.assertEqual(status, 200)
                self.assertTrue(body)
                if path == "/api/v1/synthetic-data":
                    self.assertTrue(json.loads(body)["synthetic_only"])

    async def test_not_ready_returns_503(self) -> None:
        with patch.object(repository, "is_ready", return_value=False):
            status, body = await self.request("/readyz")
        self.assertEqual(status, 503)
        self.assertIn("not ready", json.loads(body)["detail"])

    def test_generator_stays_deterministic(self) -> None:
        first = generate_dataset(seed=20261007, client_count=25, reference_date=date(2026, 1, 1))
        second = generate_dataset(seed=20261007, client_count=25, reference_date=date(2026, 1, 1))
        self.assertEqual(first, second)


if __name__ == "__main__":
    unittest.main()
