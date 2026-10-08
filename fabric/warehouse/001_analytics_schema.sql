IF SCHEMA_ID('analytics') IS NULL
    EXEC('CREATE SCHEMA analytics');
GO

DROP TABLE IF EXISTS analytics.FactCapacity;
DROP TABLE IF EXISTS analytics.FactReferral;
DROP TABLE IF EXISTS analytics.FactAppointment;
DROP TABLE IF EXISTS analytics.DimClientSegment;
DROP TABLE IF EXISTS analytics.DimProgram;
DROP TABLE IF EXISTS analytics.DimFacility;

CREATE TABLE analytics.DimFacility
(
    FacilityId int NOT NULL,
    FacilityName varchar(120) NOT NULL,
    Neighborhood varchar(80) NOT NULL,
    PlannedDailyCapacity smallint NOT NULL
);

CREATE TABLE analytics.DimProgram
(
    ProgramId int NOT NULL,
    FacilityId int NOT NULL,
    ProgramName varchar(120) NOT NULL,
    ServiceCategory varchar(80) NOT NULL
);

CREATE TABLE analytics.DimClientSegment
(
    ClientId int NOT NULL,
    AgeBand varchar(10) NOT NULL,
    DemographicGroup varchar(20) NOT NULL,
    Neighborhood varchar(80) NOT NULL
);

CREATE TABLE analytics.FactAppointment
(
    AppointmentId int NOT NULL,
    ClientId int NOT NULL,
    ProgramId int NOT NULL,
    ScheduledDate date NOT NULL,
    WaitDays smallint NOT NULL,
    AppointmentStatus varchar(20) NOT NULL
);

CREATE TABLE analytics.FactReferral
(
    ReferralId int NOT NULL,
    ClientId int NOT NULL,
    FromProgramId int NOT NULL,
    ToProgramId int NOT NULL,
    ReferralDate date NOT NULL,
    ReferralStatus varchar(20) NOT NULL,
    DaysToClose smallint NULL
);

CREATE TABLE analytics.FactCapacity
(
    CapacitySnapshotId int NOT NULL,
    FacilityId int NOT NULL,
    SnapshotDate date NOT NULL,
    AvailableSlots smallint NOT NULL,
    BookedSlots smallint NOT NULL
);
GO
