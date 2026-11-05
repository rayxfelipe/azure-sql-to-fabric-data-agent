# Demo guide: Azure SQL to Fabric Data Agent

Follow a set of synthetic community-health records from Azure SQL to analytical
answers in Microsoft Fabric.

**Allow 25-30 minutes**, plus five minutes for the optional ontology walkthrough.
All records are synthetic. Results are not findings about actual services,
residents, or clinical outcomes.

## Before you start

1. Use the already-configured demo environment. You do not need to redeploy it or
   reload the source data for this walkthrough.
2. Sign in to [Microsoft Fabric](https://app.fabric.microsoft.com) in the demo's
   directory, with permission to open the items below.
3. Make sure the primary Fabric capacity is Active. The optional ontology also
   needs the companion capacity. Presenter commands are at the end of this guide.
4. Use the standard sample dataset for the expected answers. Additional records
   change the totals.
5. Use specific dates in questions, such as **September 2026**. The sample has a
   fixed reference date of October 1, 2026; avoid questions such as "last month".

### Items used in the walkthrough

| Item | Name |
|---|---|
| Main workspace | `ws-e2e-sql-to-fabricagent` |
| Mirrored database | `CommunityHealthOLTP_Mirror` |
| Analytics pipeline | `pl_load_community_health_analytics` |
| Warehouse | `CommunityHealthAnalyticsWH` |
| Semantic model | `Community Health Access Model` |
| Published Data Agent | `SFDPH Community Health Analyst` |
| Optional ontology workspace | `ws-e2e-sql-to-fabricagent-iq` |
| Optional ontology | `CCSF_Community_Health_Demo_Ontology` |

## 1. See how the source data arrives in Fabric

1. Open the main workspace and select **CommunityHealthOLTP_Mirror**.
2. Open its replication monitor. Check that the source tables are replicating and
   their latest synchronization times are current. Start mirroring if it is stopped,
   then wait for the tables to synchronize.
3. Open the mirror's **SQL analytics endpoint** and create a SQL query:

   ```sql
   SELECT COUNT_BIG(*) AS Clients FROM health.Clients;
   SELECT COUNT_BIG(*) AS Appointments FROM health.Appointments;
   SELECT COUNT_BIG(*) AS Referrals FROM health.Referrals;
   ```

4. Run the query. The standard sample contains **5,000 clients, 90,000 appointments,
   and 12,000 referrals**.

**Explain:** Azure SQL holds the operational records. Mirroring makes a copy
available in Fabric for analytics. Replication is near-real-time, not instantaneous.

## 2. Run the analytics pipeline

1. Return to the main workspace.
2. Open **pl_load_community_health_analytics**.
3. Select **Run** and wait for the run to complete.
4. Open the run details and confirm that the activity completed successfully.

**Explain:** This pipeline prepares reporting tables in the Warehouse. It groups
appointments and referrals for analysis and excludes groups smaller than 11 records.

If replication or the pipeline is not ready, wait before continuing. Do not compare
answers from different data snapshots.

## 3. Check the reporting data in the Warehouse

1. Open **CommunityHealthAnalyticsWH**.
2. Expand the **reporting** schema. Locate the appointment, referral, and capacity
   tables.
3. Create a SQL query and run:

   ```sql
   SELECT
       SUM(AppointmentCount) AS ReportedAppointments,
       ROUND(SUM(WaitDaysTotal) * 1.0 /
           NULLIF(SUM(AppointmentCount), 0), 2) AS AverageWaitDays
   FROM reporting.CommunityHealthAccess;

   SELECT
       SUM(ReferralCount) AS ReportedReferrals,
       SUM(CompletedReferralCount) * 100.0 /
           NULLIF(SUM(ReferralCount), 0) AS ReferralCompletionPercent
   FROM reporting.ReferralPerformance;
   ```

4. Confirm **70,944 reported appointments**, **18.97 average wait days**,
   **12,000 referrals**, and **50% referral completion**.

**Why are there fewer reported appointments than source appointments?**
The reporting layer excludes small groups. The 70,944 total is therefore not the
full 90,000 source appointments, and neither count represents unique people.

Average wait is total wait days divided by reported appointments. This gives
each appointment equal weight.

## 4. Review the shared business measures

1. Open **Community Health Access Model** from the main workspace.
2. Run a refresh after the pipeline completes and wait for it to finish.
3. Explore the model's three reporting tables: **CommunityHealthAccess**,
   **ReferralPerformance**, and **FacilityCapacity**.
4. Locate the measures **Appointments**, **Average Wait Days**, **No-Show Rate**,
   and **Referral Completion Rate**.
5. Where model exploration is available, compare the measures with the Warehouse
   results from step 3.

**Explain:** The semantic model gives shared definitions to business measures.
The Data Agent uses this model when answering questions.

## 5. Ask the Data Agent

1. Open **SFDPH Community Health Analyst** and use its published experience.
2. Start a new conversation.
3. Ask the questions below. Use "entire dataset" so that an earlier date filter
   does not change the comparison.

| Question | Expected answer for the standard sample |
|---|---|
| How many reported appointments are in the entire synthetic reporting dataset? Are suppressed groups included? | 70,944; suppressed groups are excluded |
| How many reported referrals are in the entire synthetic reporting dataset? | 12,000 |
| What percentage of reported referrals were completed across the entire dataset? | 50% |
| What is the appointment-weighted average wait across the entire reporting dataset, to two decimal places? | 18.97 days |
| What is the no-show rate across the entire reporting dataset? | Approximately 19.8% |
| Which service category has the longest appointment-weighted average wait across the entire reporting dataset? | Behavioral Health, approximately 32.5 days |
| How many facility capacity snapshots exceeded 85% utilization during September 2026? | 11 snapshots, not 11 distinct facilities |

4. Compare the answers with the Warehouse results. Wording and rounding may vary;
   check the value and the scope of the question.
5. Ask: **"Can you calculate population-adjusted utilization?"** The sample has no
   population denominator, so the agent should explain that the data is missing
   rather than invent a rate.

**Explain:** These answers describe a synthetic reporting dataset. The agent's
reporting model cannot determine the full source count or how many records were
omitted. A refusal is agent behavior, not proof of enforced access permissions.

The [question bank](../fabric/data-agent/evaluation_questions.json) includes
additional SQL and DAX queries for checking the answers.

## 6. Optional: explore the business ontology

This section shows the business structure and its source mappings. **Live graph
queries and an ontology-connected second agent are not currently available in
this deployment.** Use the published agent from step 5 for live questions.

1. Switch to **ws-e2e-sql-to-fabricagent-iq**.
2. Open **CCSF_Community_Health_Demo_Ontology**.
3. Locate the five entity types:

   | Entity | Meaning |
   |---|---|
   | Facility | A location offering services |
   | Program | A service program at a facility |
   | AccessSummary | A group of appointment records |
   | ReferralSummary | A group of referral records |
   | CapacitySnapshot | A facility's available and booked capacity on a date |

4. Follow the four relationships: a Program belongs to a Facility; an AccessSummary
   and a ReferralSummary each belong to a Program; a CapacitySnapshot belongs to
   a Facility.
5. Inspect an entity's properties and source mappings. For example, Facility uses
   the **reporting.Facilities** table and the **FacilityId** key.

**Explain:** An ontology makes business concepts and relationships explicit.
The structure on screen describes those concepts; it is not a display of individual
data records and does not by itself prove graph-query execution.

## 7. Wrap up

Summarize the journey:

- Azure SQL provides the operational records.
- Mirroring brings them into Fabric.
- The Warehouse prepares aggregate reporting data.
- The semantic model defines shared measures.
- The Data Agent makes those measures accessible through questions.

Keep the scope clear: the sample does not provide population-adjusted rates,
travel distances, clinical outcomes, or causal explanations. Restricted-user
permission testing is separate from this walkthrough.

If the agent is unavailable, use the Warehouse queries and shared measures to
finish the discussion.

## Presenter shortcuts

These commands are for the presenter, not required for following the Fabric UI.
Run them from the repository root in the configured demo environment after signing
Azure CLI in to the demo's directory. Use PowerShell 7.4+; the validation script
also needs Python 3.12, `pyodbc`, and ODBC Driver 18.

### Before the session

Resume the capacities and check the data:

```powershell
.\scripts\Set-FabricCapacityState.ps1 -State Resume -Target All
.\scripts\Test-Deployment.ps1
```

For a command-line agent check, use
[Invoke-FabricDataAgent.ps1](../scripts/Invoke-FabricDataAgent.ps1) with the workspace
and Data Agent IDs from Fabric.

### After the session

Pause both demo capacities when they are no longer needed:

```powershell
.\scripts\Set-FabricCapacityState.ps1 -State Suspend -Target All
```

Confirm that the capacities show **Paused** in Azure. Pausing Fabric does not stop
Azure SQL or all storage charges.
