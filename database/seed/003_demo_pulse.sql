SET NOCOUNT ON;
SET XACT_ABORT ON;

IF NOT EXISTS (SELECT 1 FROM health.Appointments WHERE AppointmentId = 365 AND IsSynthetic = 1)
    THROW 51050, 'Apply the deterministic synthetic seed before running the live-change demonstration.', 1;
IF NOT EXISTS (SELECT 1 FROM health.Appointments WHERE AppointmentId = 900001)
    INSERT health.Appointments (AppointmentId, ClientId, ProgramId, ScheduledAt, WaitDays, AppointmentStatus)
        SELECT 900001, ClientId, ProgramId, ScheduledAt, WaitDays, AppointmentStatus
        FROM health.Appointments WHERE AppointmentId = 365 AND IsSynthetic = 1;

SELECT AppointmentId, ScheduledAt, WaitDays, AppointmentStatus
FROM health.Appointments WHERE AppointmentId = 900001;
