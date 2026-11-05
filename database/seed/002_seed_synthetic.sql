SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @ClientCount int = 5000;
DECLARE @AppointmentCount int = 90000;
DECLARE @ReferralCount int = 12000;
DECLARE @ReferenceDate date = '2026-10-01';

IF EXISTS (SELECT 1 FROM health.Clients WHERE IsSynthetic <> 1)
    OR EXISTS (SELECT 1 FROM health.Appointments WHERE IsSynthetic <> 1)
    OR EXISTS (SELECT 1 FROM health.Referrals WHERE IsSynthetic <> 1)
    OR EXISTS (SELECT 1 FROM health.Outcomes WHERE IsSynthetic <> 1)
    OR EXISTS (SELECT 1 FROM health.Facilities WHERE IsSynthetic <> 1)
    OR EXISTS (SELECT 1 FROM health.Programs WHERE IsSynthetic <> 1)
    OR EXISTS (SELECT 1 FROM health.CapacitySnapshots WHERE IsSynthetic <> 1)
    THROW 51002, 'Refusing to seed a database containing non-synthetic records.', 1;

BEGIN TRANSACTION;

MERGE health.Facilities AS target
USING (VALUES
    (1, N'Bayview Community Health Center', N'Bayview Hunters Point', 40),
    (2, N'Mission Community Health Center', N'Mission', 55),
    (3, N'Chinatown Community Health Center', N'Chinatown', 70)
) AS source (FacilityId, FacilityName, Neighborhood, PlannedDailyCapacity)
ON target.FacilityId = source.FacilityId
WHEN MATCHED THEN UPDATE SET FacilityName = source.FacilityName,
    Neighborhood = source.Neighborhood, PlannedDailyCapacity = source.PlannedDailyCapacity
WHEN NOT MATCHED THEN INSERT (FacilityId, FacilityName, Neighborhood, PlannedDailyCapacity)
    VALUES (source.FacilityId, source.FacilityName, source.Neighborhood, source.PlannedDailyCapacity);

MERGE health.Programs AS target
USING (VALUES
    (1, 1, N'Preventive Care', N'Primary Care'),
    (2, 2, N'Nutrition Support', N'Community Wellness'),
    (3, 3, N'Care Navigation', N'Referral Services'),
    (4, 1, N'Immunization Access', N'Preventive Services'),
    (5, 2, N'Behavioral Health Navigation', N'Behavioral Health')
) AS source (ProgramId, FacilityId, ProgramName, ServiceCategory)
ON target.ProgramId = source.ProgramId
WHEN MATCHED THEN UPDATE SET FacilityId = source.FacilityId,
    ProgramName = source.ProgramName, ServiceCategory = source.ServiceCategory
WHEN NOT MATCHED THEN INSERT (ProgramId, FacilityId, ProgramName, ServiceCategory)
    VALUES (source.ProgramId, source.FacilityId, source.ProgramName, source.ServiceCategory);

;WITH n AS
(
    SELECT TOP (@ClientCount) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n
    FROM sys.all_objects a CROSS JOIN sys.all_objects b
)
MERGE health.Clients AS target
USING (
SELECT
    n AS ClientId,
    2026 - (5 + ((n * 17) % 84)) AS BirthYear,
    CASE
        WHEN 5 + ((n * 17) % 84) < 18 THEN '0-17'
        WHEN 5 + ((n * 17) % 84) < 35 THEN '18-34'
        WHEN 5 + ((n * 17) % 84) < 50 THEN '35-49'
        WHEN 5 + ((n * 17) % 84) < 65 THEN '50-64'
        ELSE '65+'
    END AS AgeBand,
    CONCAT('Group ', CHAR(65 + (n % 4))) AS DemographicGroup,
    CHOOSE(1 + (n % 5), N'Bayview Hunters Point', N'Chinatown', N'Excelsior', N'Mission', N'Outer Sunset') AS Neighborhood
FROM n
) AS source ON target.ClientId = source.ClientId
WHEN MATCHED THEN UPDATE SET BirthYear = source.BirthYear, AgeBand = source.AgeBand,
    DemographicGroup = source.DemographicGroup, Neighborhood = source.Neighborhood
WHEN NOT MATCHED THEN INSERT (ClientId, BirthYear, AgeBand, DemographicGroup, Neighborhood)
    VALUES (source.ClientId, source.BirthYear, source.AgeBand, source.DemographicGroup, source.Neighborhood);

;WITH n AS
(
    SELECT TOP (@AppointmentCount) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n
    FROM sys.all_objects a CROSS JOIN sys.all_objects b CROSS JOIN sys.all_objects c
)
MERGE health.Appointments AS target
USING (
SELECT
    n AS AppointmentId,
    1 + ((n * 37) % @ClientCount) AS ClientId,
    1 + ((n * 13) % 5) AS ProgramId,
    DATEADD(minute, 480 + 30 * (n % 16), DATEADD(day, -(n % 365), CAST(@ReferenceDate AS datetime2(0)))) AS ScheduledAt,
    -- Deliberate service-level wait bands make the synthetic comparison visible, not representative.
    (n * 11) % 16 + CHOOSE(1 + ((n * 13) % 5), 2, 8, 18, 4, 25) AS WaitDays,
    CHOOSE(1 + (n % 10), 'completed', 'completed', 'completed', 'completed', 'completed',
           'completed', 'no_show', 'no_show', 'cancelled', 'scheduled') AS AppointmentStatus
FROM n
) AS source ON target.AppointmentId = source.AppointmentId
WHEN MATCHED THEN UPDATE SET ClientId = source.ClientId, ProgramId = source.ProgramId,
    ScheduledAt = source.ScheduledAt, WaitDays = source.WaitDays, AppointmentStatus = source.AppointmentStatus
WHEN NOT MATCHED THEN INSERT (AppointmentId, ClientId, ProgramId, ScheduledAt, WaitDays, AppointmentStatus)
    VALUES (source.AppointmentId, source.ClientId, source.ProgramId, source.ScheduledAt, source.WaitDays, source.AppointmentStatus);

;WITH n AS
(
    SELECT TOP (@ReferralCount) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n
    FROM sys.all_objects a CROSS JOIN sys.all_objects b
)
MERGE health.Referrals AS target
USING (
SELECT
    n AS ReferralId,
    1 + ((n * 29) % @ClientCount) AS ClientId,
    1 + (n % 5) AS FromProgramId,
    1 + ((n + 2) % 5) AS ToProgramId,
    DATEADD(day, -(n % 300), @ReferenceDate) AS ReferralDate,
    CHOOSE(1 + (n % 8), 'completed', 'completed', 'completed', 'completed', 'scheduled', 'open', 'open', 'declined') AS ReferralStatus,
    CASE WHEN n % 8 < 4 THEN 2 + ((n * 7) % 40) END AS DaysToClose
FROM n
) AS source ON target.ReferralId = source.ReferralId
WHEN MATCHED THEN UPDATE SET ClientId = source.ClientId, FromProgramId = source.FromProgramId,
    ToProgramId = source.ToProgramId, ReferralDate = source.ReferralDate,
    ReferralStatus = source.ReferralStatus, DaysToClose = source.DaysToClose
WHEN NOT MATCHED THEN INSERT (ReferralId, ClientId, FromProgramId, ToProgramId, ReferralDate, ReferralStatus, DaysToClose)
    VALUES (source.ReferralId, source.ClientId, source.FromProgramId, source.ToProgramId,
            source.ReferralDate, source.ReferralStatus, source.DaysToClose);

MERGE health.Outcomes AS target
USING (
SELECT
    AppointmentId AS OutcomeId,
    AppointmentId,
    CAST(DATEADD(day, 1, ScheduledAt) AS date) AS OutcomeDate,
    CHOOSE(1 + (AppointmentId % 3), 'care_goal_progress', 'service_connected', 'follow_up_needed') AS OutcomeType,
    1 + ((AppointmentId * 7) % 5) AS OutcomeScore
FROM health.Appointments
WHERE AppointmentStatus = 'completed'
) AS source ON target.OutcomeId = source.OutcomeId
WHEN MATCHED THEN UPDATE SET AppointmentId = source.AppointmentId, OutcomeDate = source.OutcomeDate,
    OutcomeType = source.OutcomeType, OutcomeScore = source.OutcomeScore
WHEN NOT MATCHED THEN INSERT (OutcomeId, AppointmentId, OutcomeDate, OutcomeType, OutcomeScore)
    VALUES (source.OutcomeId, source.AppointmentId, source.OutcomeDate, source.OutcomeType, source.OutcomeScore);

;WITH dates AS
(
    SELECT TOP (180) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1 AS day_offset
    FROM sys.all_objects
),
facility_dates AS
(
    SELECT f.FacilityId, f.PlannedDailyCapacity, d.day_offset,
           ROW_NUMBER() OVER (ORDER BY f.FacilityId, d.day_offset) AS snapshot_id
    FROM health.Facilities f
    CROSS JOIN dates d
)
MERGE health.CapacitySnapshots AS target
USING (
SELECT
    snapshot_id AS CapacitySnapshotId,
    FacilityId,
    DATEADD(day, -day_offset, @ReferenceDate) AS SnapshotDate,
    PlannedDailyCapacity - ((day_offset * 7 + FacilityId * 3) % PlannedDailyCapacity) AS AvailableSlots,
    (day_offset * 7 + FacilityId * 3) % PlannedDailyCapacity AS BookedSlots
FROM facility_dates
) AS source ON target.FacilityId = source.FacilityId AND target.SnapshotDate = source.SnapshotDate
WHEN MATCHED THEN UPDATE SET AvailableSlots = source.AvailableSlots, BookedSlots = source.BookedSlots
WHEN NOT MATCHED THEN INSERT (CapacitySnapshotId, FacilityId, SnapshotDate, AvailableSlots, BookedSlots)
    VALUES (source.CapacitySnapshotId, source.FacilityId, source.SnapshotDate, source.AvailableSlots, source.BookedSlots);

COMMIT TRANSACTION;
GO
