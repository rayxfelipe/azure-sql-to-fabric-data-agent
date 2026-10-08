SET NOCOUNT ON;
SET XACT_ABORT ON;

BEGIN TRANSACTION;

INSERT health.Facilities (FacilityId, FacilityName, Neighborhood, PlannedDailyCapacity)
VALUES
    (1, N'Bayview Community Health Center', N'Bayview Hunters Point', 40),
    (2, N'Mission Community Health Center', N'Mission', 55),
    (3, N'Chinatown Community Health Center', N'Chinatown', 70);

INSERT health.Programs (ProgramId, FacilityId, ProgramName, ServiceCategory)
VALUES
    (1, 1, N'Preventive Care', N'Primary Care'),
    (2, 2, N'Nutrition Support', N'Community Wellness'),
    (3, 3, N'Care Navigation', N'Referral Services'),
    (4, 1, N'Immunization Access', N'Preventive Services'),
    (5, 2, N'Behavioral Health Navigation', N'Behavioral Health');

;WITH n AS
(
    SELECT TOP (500) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n
    FROM sys.all_objects a CROSS JOIN sys.all_objects b
)
INSERT health.Clients (ClientId, BirthYear, AgeBand, DemographicGroup, Neighborhood)
SELECT
    n,
    2026 - (5 + ((n * 17) % 84)),
    CASE
        WHEN 5 + ((n * 17) % 84) < 18 THEN '0-17'
        WHEN 5 + ((n * 17) % 84) < 35 THEN '18-34'
        WHEN 5 + ((n * 17) % 84) < 50 THEN '35-49'
        WHEN 5 + ((n * 17) % 84) < 65 THEN '50-64'
        ELSE '65+'
    END,
    CONCAT('Group ', CHAR(65 + (n % 4))),
    CHOOSE(1 + (n % 5), N'Bayview Hunters Point', N'Chinatown', N'Excelsior', N'Mission', N'Outer Sunset')
FROM n;

;WITH n AS
(
    SELECT TOP (1500) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n
    FROM sys.all_objects a CROSS JOIN sys.all_objects b
)
INSERT health.Appointments
    (AppointmentId, ClientId, ProgramId, ScheduledAt, WaitDays, AppointmentStatus)
SELECT
    n,
    1 + ((n * 37) % 500),
    1 + ((n * 13) % 5),
    DATEADD(minute, 30 * (n % 16), DATEADD(day, -(n % 365), CAST('2026-10-01T08:00:00' AS datetime2(0)))),
    (n * 11) % 46,
    CHOOSE(1 + (n % 10), 'completed', 'completed', 'completed', 'completed', 'completed',
           'completed', 'no_show', 'no_show', 'cancelled', 'scheduled')
FROM n;

;WITH n AS
(
    SELECT TOP (400) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n
    FROM sys.all_objects a CROSS JOIN sys.all_objects b
)
INSERT health.Referrals
    (ReferralId, ClientId, FromProgramId, ToProgramId, ReferralDate, ReferralStatus, DaysToClose)
SELECT
    n,
    1 + ((n * 29) % 500),
    1 + (n % 5),
    1 + ((n + 2) % 5),
    DATEADD(day, -(n % 300), CAST('2026-10-01' AS date)),
    CHOOSE(1 + (n % 8), 'completed', 'completed', 'completed', 'completed', 'scheduled', 'open', 'open', 'declined'),
    CASE WHEN n % 8 < 4 THEN 2 + ((n * 7) % 40) END
FROM n;

INSERT health.Outcomes (OutcomeId, AppointmentId, OutcomeDate, OutcomeType, OutcomeScore)
SELECT
    AppointmentId,
    AppointmentId,
    CAST(DATEADD(day, 1, ScheduledAt) AS date),
    CHOOSE(1 + (AppointmentId % 3), 'care_goal_progress', 'service_connected', 'follow_up_needed'),
    1 + ((AppointmentId * 7) % 5)
FROM health.Appointments
WHERE AppointmentStatus = 'completed';

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
INSERT health.CapacitySnapshots
    (CapacitySnapshotId, FacilityId, SnapshotDate, AvailableSlots, BookedSlots)
SELECT
    snapshot_id,
    FacilityId,
    DATEADD(day, -day_offset, CAST('2026-10-01' AS date)),
    PlannedDailyCapacity - ((day_offset * 7 + FacilityId * 3) % (PlannedDailyCapacity / 2)),
    (day_offset * 7 + FacilityId * 3) % (PlannedDailyCapacity / 2)
FROM facility_dates;

COMMIT TRANSACTION;
GO
