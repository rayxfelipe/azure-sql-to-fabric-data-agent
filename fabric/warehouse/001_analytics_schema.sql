IF SCHEMA_ID('analytics') IS NULL
    EXEC('CREATE SCHEMA analytics');
IF SCHEMA_ID('reporting') IS NULL
    EXEC('CREATE SCHEMA reporting');
GO

IF OBJECT_ID('analytics.DimFacility', 'U') IS NULL
CREATE TABLE analytics.DimFacility
(
    FacilityId int NOT NULL,
    FacilityName varchar(120) NOT NULL,
    Neighborhood varchar(80) NOT NULL,
    PlannedDailyCapacity smallint NOT NULL
);

IF OBJECT_ID('analytics.DimProgram', 'U') IS NULL
CREATE TABLE analytics.DimProgram
(
    ProgramId int NOT NULL,
    FacilityId int NOT NULL,
    ProgramName varchar(120) NOT NULL,
    ServiceCategory varchar(80) NOT NULL
);

IF OBJECT_ID('analytics.DimClientSegment', 'U') IS NULL
CREATE TABLE analytics.DimClientSegment
(
    ClientId int NOT NULL,
    AgeBand varchar(10) NOT NULL,
    DemographicGroup varchar(20) NOT NULL,
    Neighborhood varchar(80) NOT NULL
);

IF OBJECT_ID('analytics.FactAppointment', 'U') IS NULL
CREATE TABLE analytics.FactAppointment
(
    AppointmentId int NOT NULL,
    ClientId int NOT NULL,
    ProgramId int NOT NULL,
    ScheduledDate date NOT NULL,
    WaitDays smallint NOT NULL,
    AppointmentStatus varchar(20) NOT NULL
);

IF OBJECT_ID('analytics.FactReferral', 'U') IS NULL
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

IF OBJECT_ID('analytics.FactCapacity', 'U') IS NULL
CREATE TABLE analytics.FactCapacity
(
    CapacitySnapshotId int NOT NULL,
    FacilityId int NOT NULL,
    SnapshotDate date NOT NULL,
    AvailableSlots smallint NOT NULL,
    BookedSlots smallint NOT NULL
);
GO

IF OBJECT_ID('reporting.CommunityHealthAccess', 'U') IS NULL
CREATE TABLE reporting.CommunityHealthAccess
(
    AccessGroupId varchar(200) NOT NULL,
    ProgramId int NOT NULL,
    FacilityId int NOT NULL,
    ScheduledDate date NOT NULL,
    ServiceCategory varchar(80) NOT NULL,
    FacilityNeighborhood varchar(80) NOT NULL,
    AgeBand varchar(10) NOT NULL,
    DemographicGroup varchar(20) NOT NULL,
    AppointmentCount bigint NOT NULL,
    CompletedCount bigint NOT NULL,
    NoShowCount bigint NOT NULL,
    WaitDaysTotal bigint NOT NULL,
    AverageWaitDays decimal(18,6) NOT NULL
);

IF OBJECT_ID('reporting.ReferralPerformance', 'U') IS NULL
CREATE TABLE reporting.ReferralPerformance
(
    ReferralGroupId varchar(200) NOT NULL,
    ProgramId int NOT NULL,
    FacilityId int NOT NULL,
    ReferralDate date NOT NULL,
    ServiceCategory varchar(80) NOT NULL,
    Neighborhood varchar(80) NOT NULL,
    ReferralCount bigint NOT NULL,
    CompletedReferralCount bigint NOT NULL,
    AverageDaysToClose decimal(18,6) NULL
);

IF OBJECT_ID('reporting.Facilities', 'U') IS NULL
CREATE TABLE reporting.Facilities
(
    FacilityId int NOT NULL,
    FacilityName varchar(120) NOT NULL,
    Neighborhood varchar(80) NOT NULL,
    PlannedDailyCapacity smallint NOT NULL
);

IF OBJECT_ID('reporting.Programs', 'U') IS NULL
CREATE TABLE reporting.Programs
(
    ProgramId int NOT NULL,
    FacilityId int NOT NULL,
    ProgramName varchar(120) NOT NULL,
    ServiceCategory varchar(80) NOT NULL
);

IF OBJECT_ID('reporting.FacilityCapacity', 'U') IS NULL
CREATE TABLE reporting.FacilityCapacity
(
    CapacitySnapshotId int NOT NULL,
    FacilityId int NOT NULL,
    FacilityName varchar(120) NOT NULL,
    Neighborhood varchar(80) NOT NULL,
    SnapshotDate date NOT NULL,
    AvailableSlots smallint NOT NULL,
    BookedSlots smallint NOT NULL,
    UtilizationRate decimal(18,6) NOT NULL
);
GO
