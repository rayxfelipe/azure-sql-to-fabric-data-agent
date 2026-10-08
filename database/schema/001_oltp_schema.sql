SET NOCOUNT ON;
SET XACT_ABORT ON;

IF SCHEMA_ID(N'health') IS NULL
    EXEC(N'CREATE SCHEMA health');
GO

IF OBJECT_ID(N'health.CapacitySnapshots', N'U') IS NOT NULL DROP TABLE health.CapacitySnapshots;
IF OBJECT_ID(N'health.Outcomes', N'U') IS NOT NULL DROP TABLE health.Outcomes;
IF OBJECT_ID(N'health.Referrals', N'U') IS NOT NULL DROP TABLE health.Referrals;
IF OBJECT_ID(N'health.Appointments', N'U') IS NOT NULL DROP TABLE health.Appointments;
IF OBJECT_ID(N'health.Clients', N'U') IS NOT NULL DROP TABLE health.Clients;
IF OBJECT_ID(N'health.Programs', N'U') IS NOT NULL DROP TABLE health.Programs;
IF OBJECT_ID(N'health.Facilities', N'U') IS NOT NULL DROP TABLE health.Facilities;
GO

CREATE TABLE health.Facilities
(
    FacilityId int NOT NULL CONSTRAINT PK_Facilities PRIMARY KEY,
    FacilityName nvarchar(120) NOT NULL,
    Neighborhood nvarchar(80) NOT NULL,
    PlannedDailyCapacity smallint NOT NULL CONSTRAINT CK_Facilities_Capacity CHECK (PlannedDailyCapacity > 0),
    IsSynthetic bit NOT NULL CONSTRAINT DF_Facilities_IsSynthetic DEFAULT (1)
);

CREATE TABLE health.Programs
(
    ProgramId int NOT NULL CONSTRAINT PK_Programs PRIMARY KEY,
    FacilityId int NOT NULL,
    ProgramName nvarchar(120) NOT NULL,
    ServiceCategory nvarchar(80) NOT NULL,
    IsSynthetic bit NOT NULL CONSTRAINT DF_Programs_IsSynthetic DEFAULT (1),
    CONSTRAINT FK_Programs_Facilities FOREIGN KEY (FacilityId) REFERENCES health.Facilities(FacilityId)
);

CREATE TABLE health.Clients
(
    ClientId int NOT NULL CONSTRAINT PK_Clients PRIMARY KEY,
    BirthYear smallint NOT NULL CONSTRAINT CK_Clients_BirthYear CHECK (BirthYear BETWEEN 1920 AND 2026),
    AgeBand varchar(10) NOT NULL,
    DemographicGroup varchar(20) NOT NULL,
    Neighborhood nvarchar(80) NOT NULL,
    IsSynthetic bit NOT NULL CONSTRAINT DF_Clients_IsSynthetic DEFAULT (1)
);

CREATE TABLE health.Appointments
(
    AppointmentId int NOT NULL CONSTRAINT PK_Appointments PRIMARY KEY,
    ClientId int NOT NULL,
    ProgramId int NOT NULL,
    ScheduledAt datetime2(0) NOT NULL,
    WaitDays smallint NOT NULL CONSTRAINT CK_Appointments_WaitDays CHECK (WaitDays >= 0),
    AppointmentStatus varchar(20) NOT NULL
        CONSTRAINT CK_Appointments_Status CHECK (AppointmentStatus IN ('completed', 'cancelled', 'no_show', 'scheduled')),
    IsSynthetic bit NOT NULL CONSTRAINT DF_Appointments_IsSynthetic DEFAULT (1),
    CONSTRAINT FK_Appointments_Clients FOREIGN KEY (ClientId) REFERENCES health.Clients(ClientId),
    CONSTRAINT FK_Appointments_Programs FOREIGN KEY (ProgramId) REFERENCES health.Programs(ProgramId)
);

CREATE TABLE health.Referrals
(
    ReferralId int NOT NULL CONSTRAINT PK_Referrals PRIMARY KEY,
    ClientId int NOT NULL,
    FromProgramId int NOT NULL,
    ToProgramId int NOT NULL,
    ReferralDate date NOT NULL,
    ReferralStatus varchar(20) NOT NULL
        CONSTRAINT CK_Referrals_Status CHECK (ReferralStatus IN ('open', 'scheduled', 'completed', 'declined')),
    DaysToClose smallint NULL CONSTRAINT CK_Referrals_DaysToClose CHECK (DaysToClose IS NULL OR DaysToClose >= 0),
    IsSynthetic bit NOT NULL CONSTRAINT DF_Referrals_IsSynthetic DEFAULT (1),
    CONSTRAINT FK_Referrals_Clients FOREIGN KEY (ClientId) REFERENCES health.Clients(ClientId),
    CONSTRAINT FK_Referrals_FromProgram FOREIGN KEY (FromProgramId) REFERENCES health.Programs(ProgramId),
    CONSTRAINT FK_Referrals_ToProgram FOREIGN KEY (ToProgramId) REFERENCES health.Programs(ProgramId)
);

CREATE TABLE health.Outcomes
(
    OutcomeId int NOT NULL CONSTRAINT PK_Outcomes PRIMARY KEY,
    AppointmentId int NOT NULL,
    OutcomeDate date NOT NULL,
    OutcomeType varchar(30) NOT NULL,
    OutcomeScore tinyint NOT NULL CONSTRAINT CK_Outcomes_Score CHECK (OutcomeScore BETWEEN 1 AND 5),
    IsSynthetic bit NOT NULL CONSTRAINT DF_Outcomes_IsSynthetic DEFAULT (1),
    CONSTRAINT FK_Outcomes_Appointments FOREIGN KEY (AppointmentId) REFERENCES health.Appointments(AppointmentId)
);

CREATE TABLE health.CapacitySnapshots
(
    CapacitySnapshotId int NOT NULL CONSTRAINT PK_CapacitySnapshots PRIMARY KEY,
    FacilityId int NOT NULL,
    SnapshotDate date NOT NULL,
    AvailableSlots smallint NOT NULL CONSTRAINT CK_Capacity_Available CHECK (AvailableSlots >= 0),
    BookedSlots smallint NOT NULL CONSTRAINT CK_Capacity_Booked CHECK (BookedSlots >= 0),
    IsSynthetic bit NOT NULL CONSTRAINT DF_Capacity_IsSynthetic DEFAULT (1),
    CONSTRAINT UQ_Capacity_FacilityDate UNIQUE (FacilityId, SnapshotDate),
    CONSTRAINT FK_Capacity_Facilities FOREIGN KEY (FacilityId) REFERENCES health.Facilities(FacilityId)
);

CREATE INDEX IX_Appointments_ScheduledAt ON health.Appointments(ScheduledAt) INCLUDE (ProgramId, AppointmentStatus, WaitDays);
CREATE INDEX IX_Referrals_ReferralDate ON health.Referrals(ReferralDate) INCLUDE (ReferralStatus, DaysToClose);
GO
