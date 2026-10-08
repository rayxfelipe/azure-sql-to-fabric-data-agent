from datetime import date, datetime, time, timedelta, timezone
from random import Random
from uuid import NAMESPACE_URL, uuid5

from faker import Faker

from .models import (
    Appointment,
    AppointmentStatus,
    Facility,
    ServiceProgram,
    SyntheticClient,
    SyntheticDataset,
)

NEIGHBORHOODS = (
    "Bayview Hunters Point",
    "Chinatown",
    "Excelsior",
    "Mission",
    "Outer Sunset",
)
DEMOGRAPHIC_GROUPS = (
    "Group A",
    "Group B",
    "Group C",
    "Group D",
)
PROGRAM_SPECS = (
    ("Preventive Care", "Primary Care"),
    ("Nutrition Support", "Community Wellness"),
    ("Care Navigation", "Referral Services"),
)
STATUSES = (
    AppointmentStatus.COMPLETED,
    AppointmentStatus.COMPLETED,
    AppointmentStatus.COMPLETED,
    AppointmentStatus.NO_SHOW,
    AppointmentStatus.CANCELLED,
    AppointmentStatus.SCHEDULED,
)


def _stable_id(entity: str, seed: int, index: int) -> str:
    return str(uuid5(NAMESPACE_URL, f"synthetic-health/{seed}/{entity}/{index}"))


def _age_band(age: int) -> str:
    if age < 18:
        return "0-17"
    if age < 35:
        return "18-34"
    if age < 50:
        return "35-49"
    if age < 65:
        return "50-64"
    return "65+"


def generate_dataset(
    *,
    seed: int,
    client_count: int,
    reference_date: date,
) -> SyntheticDataset:
    """Create repeatable, non-identifying demonstration records."""
    if client_count < 1:
        raise ValueError("client_count must be at least 1")

    random = Random(seed)
    faker = Faker("en_US")
    faker.seed_instance(seed)

    facilities = [
        Facility(
            facility_id=_stable_id("facility", seed, index),
            name=f"{faker.city()} Community Health Center",
            neighborhood=NEIGHBORHOODS[index % len(NEIGHBORHOODS)],
            planned_daily_capacity=40 + index * 15,
        )
        for index in range(3)
    ]
    programs = [
        ServiceProgram(
            program_id=_stable_id("program", seed, index),
            facility_id=facilities[index % len(facilities)].facility_id,
            name=name,
            service_category=category,
        )
        for index, (name, category) in enumerate(PROGRAM_SPECS)
    ]

    clients: list[SyntheticClient] = []
    appointments: list[Appointment] = []
    for index in range(client_count):
        age = random.randint(5, 88)
        client = SyntheticClient(
            client_id=_stable_id("client", seed, index),
            birth_year=reference_date.year - age,
            age_band=_age_band(age),
            demographic_group=random.choice(DEMOGRAPHIC_GROUPS),
            neighborhood=random.choice(NEIGHBORHOODS),
        )
        clients.append(client)

        program = random.choice(programs)
        wait_days = random.randint(0, 45)
        scheduled_date = reference_date - timedelta(days=random.randint(0, 180))
        scheduled_at = datetime.combine(
            scheduled_date,
            time(hour=random.randint(8, 16), minute=random.choice((0, 30))),
            tzinfo=timezone.utc,
        )
        appointments.append(
            Appointment(
                appointment_id=_stable_id("appointment", seed, index),
                client_id=client.client_id,
                program_id=program.program_id,
                scheduled_at=scheduled_at,
                wait_days=wait_days,
                status=random.choice(STATUSES),
            )
        )

    return SyntheticDataset(
        seed=seed,
        reference_date=reference_date,
        clients=clients,
        facilities=facilities,
        programs=programs,
        appointments=appointments,
    )
