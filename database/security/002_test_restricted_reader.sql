SET NOCOUNT ON;

IF NOT EXISTS (SELECT 1 FROM reporting.CommunityHealthAccess)
    THROW 51040, 'The restricted identity cannot read nonempty reporting data.', 1;

DECLARE @Denied bit = 0;
BEGIN TRY
    EXEC('SELECT TOP (1) AppointmentId FROM analytics.FactAppointment');
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 229 SET @Denied = 1;
    ELSE THROW;
END CATCH;
IF @Denied = 0
    THROW 51041, 'This identity can read raw appointments. Do not present it as a restricted reader.', 1;

SELECT 'PASS: reporting is readable and raw appointment access is denied for this SQL identity.' AS PermissionCheck;
