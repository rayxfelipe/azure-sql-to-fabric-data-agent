# Azure SQL to Microsoft Fabric Data Agent

An end-to-end demonstration of turning operational data in Azure SQL into
analytics and natural-language answers in Microsoft Fabric.

The scenario uses **synthetic community-health data**: appointments, referrals,
programs, facilities, and service capacity. No real patient or customer records
are used.

**Start here:** [Step-by-step demo guide](docs/presenter-runbook.md).

## What the demo shows

- Replicate Azure SQL data into Fabric using mirroring.
- Prepare aggregate reporting tables in a Fabric Warehouse.
- Define shared business measures in a Direct Lake semantic model.
- Ask a Fabric Data Agent questions about service access and capacity.
- Explore an optional ontology that describes the business concepts and relationships.

Example questions:

- How many reported appointments are in the dataset?
- Which service category has the longest average wait?
- What percentage of referrals were completed?
- How many facility capacity snapshots exceeded 85% utilization in September 2026?

## How the data moves

1. **Azure SQL** holds the synthetic operational records.
2. **Fabric mirroring** replicates those records into OneLake.
3. **A data pipeline and Warehouse** prepare reporting tables and exclude small
   appointment and referral groups.
4. **A semantic model** defines measures such as average wait, no-show rate, and
   referral completion.
5. **A Data Agent** uses that model to answer questions in natural language.

The optional ontology describes facilities, programs, access summaries, referral
summaries, and capacity snapshots. The current demo covers its structure and
source mappings; live graph queries and an ontology-connected second agent are
not currently available in this deployment.

## Sample dataset

| Record type | Count |
|---|---:|
| Synthetic clients | 5,000 |
| Source appointments | 90,000 |
| Referrals | 12,000 |
| Facility capacity snapshots | 540 |

The standard reporting dataset contains **70,944 appointments** after excluding
groups smaller than 11 records. It uses a fixed reference date of October 1, 2026.
These are sample values, not findings about actual services or residents.

## Repository contents

| Folder | Contents |
|---|---|
| [database](database) | Source schema, synthetic data, validation queries, and access-control examples |
| [fabric](fabric) | Warehouse, pipeline, semantic-model, ontology, and Data Agent definitions |
| [scripts](scripts) | Deployment, validation, agent-query, and capacity-management tools |
| [infra](infra) | Azure infrastructure definitions |
| [src](src) | Optional local FastAPI application for exploring synthetic data |
| [tests](tests) | Automated data, API, model-definition, and tooling checks |
| [docs](docs) | Demo guide and deployment information |

## Run the demo

Follow the [demo guide](docs/presenter-runbook.md) in an already-configured
environment with the required Fabric workspace access and active capacities.
The deployment scripts contain settings for the sample environment; review those
settings before using them in another environment.

### Optional local API

The local API generates an in-memory dataset. It does not populate Azure SQL or
feed the Fabric demonstration.

With Python 3.12:

```powershell
py -3.12 -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install -r requirements.txt
uvicorn main:app --host 127.0.0.1 --port 8000
```

Open `http://127.0.0.1:8000/docs` to explore the API.

## Privacy and scope

- All records and patterns are synthetic; this is not a clinical application.
- Reporting totals count records, not distinct people or population-adjusted rates.
- Small-group filtering illustrates a reporting control, not a complete production
  privacy solution. Production use requires separate security and governance review.
- Pause Fabric capacities after use. Azure SQL and some storage charges continue
  while Fabric is paused.
