from .models import SyntheticDataset


class InMemoryDatasetRepository:
    """Temporary local data layer; replace during the database scaffold phase."""

    def __init__(self, dataset: SyntheticDataset) -> None:
        self._dataset = dataset

    def get(self) -> SyntheticDataset:
        return self._dataset

    def is_ready(self) -> bool:
        return bool(self._dataset.clients and self._dataset.appointments)
