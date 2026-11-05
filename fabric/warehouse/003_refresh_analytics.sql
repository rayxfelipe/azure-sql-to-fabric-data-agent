SET NOCOUNT ON;

IF NOT EXISTS (SELECT 1 FROM [CommunityHealthOLTP_Mirror].[health].[Appointments])
    THROW 51020, 'Mirrored appointments are not ready. Wait for replication before refreshing.', 1;
IF NOT EXISTS (SELECT 1 FROM [CommunityHealthOLTP_Mirror].[health].[Referrals])
    THROW 51021, 'Mirrored referrals are not ready. Wait for replication before refreshing.', 1;
IF (SELECT COUNT_BIG(*) FROM [CommunityHealthOLTP_Mirror].[health].[Clients]) < 5000
    OR (SELECT COUNT_BIG(*) FROM [CommunityHealthOLTP_Mirror].[health].[Appointments]) < 90000
    OR (SELECT COUNT_BIG(*) FROM [CommunityHealthOLTP_Mirror].[health].[Referrals]) < 12000
    THROW 51025, 'The upgraded synthetic seed has not finished replicating. Run source initialization and wait for table replication.', 1;

BEGIN TRY
    BEGIN TRANSACTION;

    DELETE FROM reporting.CommunityHealthAccess;
    DELETE FROM reporting.ReferralPerformance;
    DELETE FROM reporting.FacilityCapacity;
    DELETE FROM reporting.Programs;
    DELETE FROM reporting.Facilities;
    DELETE FROM analytics.FactCapacity;
    DELETE FROM analytics.FactReferral;
    DELETE FROM analytics.FactAppointment;
    DELETE FROM analytics.DimClientSegment;
    DELETE FROM analytics.DimProgram;
    DELETE FROM analytics.DimFacility;

    INSERT analytics.DimFacility
        SELECT FacilityId, FacilityName, Neighborhood, PlannedDailyCapacity FROM [CommunityHealthOLTP_Mirror].[health].[Facilities];
    INSERT analytics.DimProgram
        SELECT ProgramId, FacilityId, ProgramName, ServiceCategory FROM [CommunityHealthOLTP_Mirror].[health].[Programs];
    INSERT analytics.DimClientSegment
        SELECT ClientId, AgeBand, DemographicGroup, Neighborhood FROM [CommunityHealthOLTP_Mirror].[health].[Clients];
    INSERT analytics.FactAppointment
        SELECT AppointmentId, ClientId, ProgramId, CAST(ScheduledAt AS date), WaitDays, AppointmentStatus FROM [CommunityHealthOLTP_Mirror].[health].[Appointments];
    INSERT analytics.FactReferral
        SELECT ReferralId, ClientId, FromProgramId, ToProgramId, ReferralDate, ReferralStatus, DaysToClose FROM [CommunityHealthOLTP_Mirror].[health].[Referrals];
    INSERT analytics.FactCapacity
        SELECT CapacitySnapshotId, FacilityId, SnapshotDate, AvailableSlots, BookedSlots FROM [CommunityHealthOLTP_Mirror].[health].[CapacitySnapshots];

    IF NOT EXISTS (SELECT 1 FROM analytics.vw_CommunityHealthAccess)
        THROW 51022, 'All appointment groups were suppressed. Upgrade the synthetic seed or review the reporting grain; do not lower the privacy threshold.', 1;
    IF NOT EXISTS (SELECT 1 FROM analytics.vw_ReferralPerformance)
        THROW 51023, 'All referral groups were suppressed. Upgrade the synthetic seed or review the reporting grain; do not lower the privacy threshold.', 1;
    IF NOT EXISTS (SELECT 1 FROM analytics.FactCapacity)
        THROW 51024, 'No capacity snapshots were mirrored.', 1;

    INSERT reporting.CommunityHealthAccess
        SELECT AccessGroupId, ProgramId, FacilityId, ScheduledDate, ServiceCategory, FacilityNeighborhood,
               AgeBand, DemographicGroup, AppointmentCount, CompletedCount, NoShowCount, WaitDaysTotal, AverageWaitDays
        FROM analytics.vw_CommunityHealthAccess;
    INSERT reporting.ReferralPerformance
        SELECT ReferralGroupId, ProgramId, FacilityId, ReferralDate, ServiceCategory, Neighborhood,
               ReferralCount, CompletedReferralCount, AverageDaysToClose
        FROM analytics.vw_ReferralPerformance;
    INSERT reporting.Facilities SELECT * FROM analytics.DimFacility;
    INSERT reporting.Programs SELECT * FROM analytics.DimProgram;
    INSERT reporting.FacilityCapacity
        SELECT c.CapacitySnapshotId, c.FacilityId, f.FacilityName, f.Neighborhood,
               c.SnapshotDate, c.AvailableSlots, c.BookedSlots,
               CAST(c.BookedSlots AS decimal(18,6)) / NULLIF(c.AvailableSlots + c.BookedSlots, 0)
        FROM analytics.FactCapacity c
        JOIN analytics.DimFacility f ON f.FacilityId = c.FacilityId;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
