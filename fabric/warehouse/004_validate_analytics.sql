SET NOCOUNT ON;

IF NOT EXISTS (SELECT 1 FROM reporting.CommunityHealthAccess)
    THROW 51030, 'Governed appointment data is empty.', 1;
IF NOT EXISTS (SELECT 1 FROM reporting.ReferralPerformance)
    THROW 51031, 'Governed referral data is empty.', 1;
IF NOT EXISTS (SELECT 1 FROM reporting.FacilityCapacity)
    THROW 51032, 'Facility capacity data is empty.', 1;
IF EXISTS (SELECT 1 FROM reporting.CommunityHealthAccess WHERE AppointmentCount < 11)
    OR EXISTS (SELECT 1 FROM reporting.ReferralPerformance WHERE ReferralCount < 11)
    THROW 51033, 'A materialized reporting group violates the suppression threshold.', 1;
IF EXISTS (SELECT AccessGroupId FROM reporting.CommunityHealthAccess GROUP BY AccessGroupId HAVING COUNT_BIG(*) <> 1)
    OR EXISTS (SELECT ReferralGroupId FROM reporting.ReferralPerformance GROUP BY ReferralGroupId HAVING COUNT_BIG(*) <> 1)
    OR EXISTS (SELECT FacilityId FROM reporting.Facilities GROUP BY FacilityId HAVING COUNT_BIG(*) <> 1)
    OR EXISTS (SELECT ProgramId FROM reporting.Programs GROUP BY ProgramId HAVING COUNT_BIG(*) <> 1)
    OR EXISTS (SELECT CapacitySnapshotId FROM reporting.FacilityCapacity GROUP BY CapacitySnapshotId HAVING COUNT_BIG(*) <> 1)
    THROW 51034, 'Ontology aggregate keys are not unique.', 1;
IF EXISTS (SELECT 1 FROM reporting.FacilityCapacity WHERE UtilizationRate < 0 OR UtilizationRate > 1)
    THROW 51035, 'Invalid capacity utilization.', 1;
IF EXISTS (SELECT 1 FROM reporting.Programs p LEFT JOIN reporting.Facilities f ON f.FacilityId = p.FacilityId WHERE f.FacilityId IS NULL)
    OR EXISTS (SELECT 1 FROM reporting.CommunityHealthAccess a LEFT JOIN reporting.Programs p ON p.ProgramId = a.ProgramId WHERE p.ProgramId IS NULL)
    OR EXISTS (SELECT 1 FROM reporting.ReferralPerformance r LEFT JOIN reporting.Programs p ON p.ProgramId = r.ProgramId WHERE p.ProgramId IS NULL)
    OR EXISTS (SELECT 1 FROM reporting.FacilityCapacity c LEFT JOIN reporting.Facilities f ON f.FacilityId = c.FacilityId WHERE f.FacilityId IS NULL)
    THROW 51036, 'A reporting relationship points to a missing entity.', 1;

SELECT
    SUM(AppointmentCount) AS ReportedAppointments,
    SUM(CompletedCount) AS ReportedCompletedAppointments,
    SUM(NoShowCount) * 1.0 / NULLIF(SUM(AppointmentCount), 0) AS NoShowRate,
    SUM(WaitDaysTotal) * 1.0 / NULLIF(SUM(AppointmentCount), 0) AS AverageWaitDays
FROM reporting.CommunityHealthAccess;

SELECT
    SUM(ReferralCount) AS ReportedReferrals,
    SUM(CompletedReferralCount) * 1.0 / NULLIF(SUM(ReferralCount), 0) AS ReferralCompletionRate
FROM reporting.ReferralPerformance;

SELECT
    (SELECT COUNT_BIG(*) FROM analytics.FactAppointment) AS SourceAppointments,
    (SELECT SUM(AppointmentCount) FROM reporting.CommunityHealthAccess) AS ReportedAppointments,
    (SELECT COUNT_BIG(*) FROM reporting.CommunityHealthAccess) AS VisibleAppointmentGroups,
    (SELECT COUNT_BIG(*) FROM reporting.ReferralPerformance) AS VisibleReferralGroups;
