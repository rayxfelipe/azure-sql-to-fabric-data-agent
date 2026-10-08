from datetime import date, datetime
from enum import StrEnum

from pydantic import BaseModel, Field


class AppointmentStatus(StrEnum):
    COMPLETED = "completed"
    CANCELLED = "cancelled"
    NO_SHOW = "no_show"
    SCHEDULED = "scheduled"


class SyntheticClient(BaseModel):
    client_id: str
    birth_year: int = Field(ge=1920, le=2026)
    age_band: str
    demographic_group: str
    neighborhood: str


class Facility(BaseModel):
    facility_id: str
    name: str
    neighborhood: str
    planned_daily_capacity: int = Field(gt=0)


class ServiceProgram(BaseModel):
    program_id: str
    facility_id: str
    name: str
    service_category: str


class Appointment(BaseModel):
    appointment_id: str
    client_id: str
    program_id: str
    scheduled_at: datetime
    wait_days: int = Field(ge=0)
    status: AppointmentStatus


class SyntheticDataset(BaseModel):
    schema_version: str = "1.0"
    synthetic_only: bool = True
    seed: int
    reference_date: date
    clients: list[SyntheticClient]
    facilities: list[Facility]
    programs: list[ServiceProgram]
    appointments: list[Appointment]
