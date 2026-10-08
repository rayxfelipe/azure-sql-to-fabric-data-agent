import os
from datetime import date

import uvicorn
from fastapi import FastAPI, HTTPException, status
from fastapi.middleware.cors import CORSMiddleware

from .generator import generate_dataset
from .models import SyntheticDataset
from .repository import InMemoryDatasetRepository


def _integer_setting(name: str, default: int) -> int:
    raw_value = os.getenv(name, str(default))
    try:
        return int(raw_value)
    except ValueError as exc:
        raise RuntimeError(f"{name} must be an integer") from exc


def _date_setting(name: str, default: str) -> date:
    raw_value = os.getenv(name, default)
    try:
        return date.fromisoformat(raw_value)
    except ValueError as exc:
        raise RuntimeError(f"{name} must use YYYY-MM-DD format") from exc


repository = InMemoryDatasetRepository(
    generate_dataset(
        seed=_integer_setting("SYNTHETIC_DATA_SEED", 20261007),
        client_count=_integer_setting("SYNTHETIC_CLIENT_COUNT", 25),
        reference_date=_date_setting("SYNTHETIC_REFERENCE_DATE", "2026-01-01"),
    )
)

app = FastAPI(
    title="Synthetic Community Health Service",
    description="Deterministic synthetic data for local public-health analytics demonstrations.",
    version="0.1.0",
)
origins = [
    origin.strip()
    for origin in os.getenv(
        "CORS_ORIGINS", "http://localhost:3000,http://localhost:8000"
    ).split(",")
    if origin.strip()
]
app.add_middleware(
    CORSMiddleware,
    allow_origins=origins,
    allow_credentials=False,
    allow_methods=["GET"],
    allow_headers=["*"],
)


@app.get("/healthz", tags=["health"])
def healthz() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/readyz", tags=["health"])
def readyz() -> dict[str, str]:
    if not repository.is_ready():
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Synthetic dataset is not ready",
        )
    return {"status": "ready"}


@app.get("/api/v1/synthetic-data", response_model=SyntheticDataset, tags=["data"])
def synthetic_data() -> SyntheticDataset:
    return repository.get()


if __name__ == "__main__":
    uvicorn.run(
        "src.community_health.main:app",
        host="0.0.0.0",
        port=_integer_setting("PORT", 8000),
    )
