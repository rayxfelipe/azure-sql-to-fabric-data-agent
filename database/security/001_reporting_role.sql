IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'community_health_demo_reader')
    EXEC('CREATE ROLE community_health_demo_reader');
GO
GRANT SELECT ON SCHEMA::reporting TO community_health_demo_reader;
DENY SELECT ON SCHEMA::analytics TO community_health_demo_reader;
GO
