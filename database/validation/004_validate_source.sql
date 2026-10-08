SET NOCOUNT ON;

IF EXISTS
(
    SELECT 1
    FROM sys.columns
    WHERE object_id IN
    (
        OBJECT_ID(N'health.Clients'),
        OBJECT_ID(N'health.Appointments'),
        OBJECT_ID(N'health.Referrals'),
        OBJECT_ID(N'health.Outcomes')
    )
    AND LOWER(name) IN ('firstname', 'lastname', 'fullname', 'email', 'phone', 'address', 'ssn', 'mrn')
)
    THROW 51000, 'Direct identifier column detected.', 1;

IF EXISTS
(
    SELECT 1
    FROM
    (
        SELECT MIN(CAST(IsSynthetic AS tinyint)) AS IsSynthetic FROM health.Clients
        UNION ALL SELECT MIN(CAST(IsSynthetic AS tinyint)) FROM health.Appointments
        UNION ALL SELECT MIN(CAST(IsSynthetic AS tinyint)) FROM health.Referrals
        UNION ALL SELECT MIN(CAST(IsSynthetic AS tinyint)) FROM health.Outcomes
    ) checks
    WHERE IsSynthetic <> 1
)
    THROW 51001, 'Non-synthetic row detected.', 1;

SELECT 'Facilities' AS EntityName, COUNT_BIG(*) AS RowCount FROM health.Facilities
UNION ALL SELECT 'Programs', COUNT_BIG(*) FROM health.Programs
UNION ALL SELECT 'Clients', COUNT_BIG(*) FROM health.Clients
UNION ALL SELECT 'Appointments', COUNT_BIG(*) FROM health.Appointments
UNION ALL SELECT 'Referrals', COUNT_BIG(*) FROM health.Referrals
UNION ALL SELECT 'Outcomes', COUNT_BIG(*) FROM health.Outcomes
UNION ALL SELECT 'CapacitySnapshots', COUNT_BIG(*) FROM health.CapacitySnapshots;
GO
