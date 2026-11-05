# Deployment summary

This environment demonstrates how synthetic community-health data moves from
Azure SQL into Microsoft Fabric for reporting and natural-language questions.

For the walkthrough, use the [step-by-step demo guide](presenter-runbook.md).

## Environment

| Component | Configuration |
|---|---|
| Azure resource group | `rg-e2e-sql-to-fabricagent` |
| Azure SQL server | `sql-e2e-fabricagent-dev-3af2`; private access and Microsoft Entra authentication |
| Azure SQL database | `sqldb-community-health`; Standard S3, 100 DTU |
| Virtual network | `vnet-e2e-fabricagent` |
| Key Vault | `kv-e2e-fabric-3af2` |
| Main Fabric capacity | `fabriccapacitydemo001b`, West US 3 |
| Main workspace | `ws-e2e-sql-to-fabricagent` |
| Mirrored database | `CommunityHealthOLTP_Mirror` |
| Source initialization pipeline | `pl_initialize_azure_sql_source` |
| Analytics pipeline | `pl_load_community_health_analytics` |
| Warehouse | `CommunityHealthAnalyticsWH` |
| Semantic model | `Community Health Access Model` |
| Published Data Agent | `SFDPH Community Health Analyst` |
| Companion Fabric capacity | `fabriccapacitydemo001`, West US |
| Companion workspace | `ws-e2e-sql-to-fabricagent-iq` |
| Optional ontology | `CCSF_Community_Health_Demo_Ontology` |
| Optional OneLake projection | `CommunityHealthOntologyLH`; five shortcuts to Warehouse reporting tables |

## Data flow

1. **Azure SQL** stores synthetic clients, appointments, referrals, programs,
   facilities, and capacity records.
2. **Fabric mirroring** replicates the operational records into OneLake through
   the private source connection and Fabric VNet gateway.
3. **The analytics pipeline** prepares Warehouse reporting tables using a full
   refresh. It groups appointment and referral records and excludes small groups.
4. **The Direct Lake semantic model** defines shared measures over the reporting data.
5. **The published Data Agent** uses the semantic model to answer questions.

The local FastAPI application is a separate, in-memory sample. It does not write
to Azure SQL or supply data to this deployed path.

## Reporting tables

The Warehouse's `reporting` schema contains five tables:

| Table | Purpose |
|---|---|
| `Facilities` | Facility names, neighborhoods, and planned capacity |
| `Programs` | Service programs and their facilities |
| `CommunityHealthAccess` | Appointment summaries, completion, no-shows, and wait times |
| `ReferralPerformance` | Referral summaries and completion |
| `FacilityCapacity` | Available and booked capacity by facility and date |

The semantic model uses the three summary tables. The ontology maps its business
concepts to all five reporting tables.

Average wait is total wait days divided by reported appointments. Referral
completion and no-show rates use their respective reported record counts.

## Standard sample values

The sample uses a fixed reference date of **October 1, 2026**. These values apply
to the standard dataset; adding records changes the results.

| Measure | Value |
|---|---:|
| Synthetic clients | 5,000 |
| Source appointments | 90,000 |
| Reported appointments | 70,944 |
| Reported referrals | 12,000 |
| Referral completion | 50% |
| Appointment-weighted average wait | 18.97 days |
| No-show rate | Approximately 19.8% |
| Facility capacity snapshots | 540 |
| September 2026 snapshots above 85% utilization | 11 |

Appointment and referral reporting groups smaller than 11 records are excluded.
Reported appointments therefore differ from the source total. These are record
counts, not distinct people or population-adjusted rates.

All records and service patterns are synthetic, not findings about actual services.

## Optional ontology

The companion workspace contains an ontology with five entity types:
**Facility, Program, AccessSummary, ReferralSummary, and CapacitySnapshot**.
Four relationships connect programs to facilities, access and referral summaries
to programs, and capacity snapshots to facilities.

The ontology's structure, properties, and source mappings can be explored.
**Live graph queries and an ontology-connected second agent are not currently
available in this deployment.** Use the published semantic-model Data Agent for
the question-and-answer portion of the demo.

The optional Lakehouse provides OneLake shortcuts to the same reporting tables.
The ontology's configured source is the Warehouse reporting schema.

## Access and privacy

- The Azure SQL source uses private connectivity and Microsoft Entra authentication.
- Credentials and local reference material are not included in source control.
- The agent uses aggregate reporting tables rather than client-level source records.
- Small-group filtering is an illustrative reporting control, not a complete
  production privacy solution.
- Restricted-user SQL, OneLake, model, and published-agent permission testing is
  separate from this demo and has not been completed.

## Running and checking the demo

- Follow the [demo guide](presenter-runbook.md) for preparation and the Fabric walkthrough.
- Use [Test-Deployment.ps1](../scripts/Test-Deployment.ps1) to check the data path,
  pipeline completion, reporting tables, and data-quality rules.
- Use the [question bank](../fabric/data-agent/evaluation_questions.json) to compare
  agent answers with SQL and DAX.
- Use [Invoke-FabricDataAgent.ps1](../scripts/Invoke-FabricDataAgent.ps1) for a
  command-line check of the published agent.

No Power BI report is included; the walkthrough uses Warehouse queries, model
exploration, and the published agent.

## Cost management

The main capacity must be Active for the reporting and agent demonstration.
The optional ontology also needs the companion capacity.

Pause demo capacities when they are no longer needed, using
[Set-FabricCapacityState.ps1](../scripts/Set-FabricCapacityState.ps1).
Pausing Fabric does not stop Azure SQL or all storage charges.
