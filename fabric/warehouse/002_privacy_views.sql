CREATE VIEW analytics.vw_CommunityHealthAccess
AS
WITH grouped AS
(
    SELECT
        a.ScheduledDate,
        p.ServiceCategory,
        f.Neighborhood AS FacilityNeighborhood,
        c.AgeBand,
        c.DemographicGroup,
        COUNT_BIG(*) AS AppointmentCount,
        SUM(CASE WHEN a.AppointmentStatus = 'completed' THEN 1 ELSE 0 END) AS CompletedCount,
        SUM(CASE WHEN a.AppointmentStatus = 'no_show' THEN 1 ELSE 0 END) AS NoShowCount,
        AVG(CAST(a.WaitDays AS decimal(10,2))) AS AverageWaitDays
    FROM analytics.FactAppointment a
    JOIN analytics.DimProgram p ON p.ProgramId = a.ProgramId
    JOIN analytics.DimFacility f ON f.FacilityId = p.FacilityId
    JOIN analytics.DimClientSegment c ON c.ClientId = a.ClientId
    GROUP BY a.ScheduledDate, p.ServiceCategory, f.Neighborhood, c.AgeBand, c.DemographicGroup
)
SELECT
    ScheduledDate,
    ServiceCategory,
    FacilityNeighborhood,
    AgeBand,
    DemographicGroup,
    AppointmentCount,
    CompletedCount,
    NoShowCount,
    AverageWaitDays
FROM grouped
WHERE AppointmentCount >= 11;
GO

CREATE VIEW analytics.vw_ReferralPerformance
AS
SELECT
    r.ReferralDate,
    p.ServiceCategory,
    c.Neighborhood,
    COUNT_BIG(*) AS ReferralCount,
    SUM(CASE WHEN r.ReferralStatus = 'completed' THEN 1 ELSE 0 END) AS CompletedReferralCount,
    AVG(CAST(r.DaysToClose AS decimal(10,2))) AS AverageDaysToClose
FROM analytics.FactReferral r
JOIN analytics.DimProgram p ON p.ProgramId = r.ToProgramId
JOIN analytics.DimClientSegment c ON c.ClientId = r.ClientId
GROUP BY r.ReferralDate, p.ServiceCategory, c.Neighborhood
HAVING COUNT_BIG(*) >= 11;
GO
