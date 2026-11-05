from datetime import date, timedelta
import json
from pathlib import Path
import re
import sqlite3
import unittest


ROOT = Path(__file__).resolve().parents[1]


class AnalyticsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.connection = sqlite3.connect(":memory:")
        cls.connection.create_function("CONCAT", -1, lambda *parts: "".join(str(part) for part in parts))
        for schema in ("analytics", "reporting"):
            cls.connection.execute(f"ATTACH DATABASE ':memory:' AS {schema}")
        schema_sql = (ROOT / "fabric" / "warehouse" / "001_analytics_schema.sql").read_text()
        for statement in re.findall(r"CREATE TABLE [\w.]+\s*\([^;]+\);", schema_sql):
            cls.connection.execute(statement)

        seed = (ROOT / "database" / "seed" / "002_seed_synthetic.sql").read_text()
        counts = {
            name: int(count)
            for name, count in re.findall(r"DECLARE @(\w+Count) int = (\d+);", seed)
        }
        for formula in (
            "1 + ((n * 37) % @ClientCount)",
            "1 + ((n * 13) % 5)",
            "(n * 11) % 16 + CHOOSE(1 + ((n * 13) % 5), 2, 8, 18, 4, 25)",
            "1 + ((n * 29) % @ClientCount)",
            "1 + ((n + 2) % 5)",
        ):
            if formula not in seed:
                raise AssertionError(f"Update the independent seed reproduction for {formula}")
        cls.insert("DimFacility", [
            (1, "Bayview Community Health Center", "Bayview Hunters Point", 40),
            (2, "Mission Community Health Center", "Mission", 55),
            (3, "Chinatown Community Health Center", "Chinatown", 70),
        ])
        cls.insert("DimProgram", [
            (1, 1, "Preventive Care", "Primary Care"),
            (2, 2, "Nutrition Support", "Community Wellness"),
            (3, 3, "Care Navigation", "Referral Services"),
            (4, 1, "Immunization Access", "Preventive Services"),
            (5, 2, "Behavioral Health Navigation", "Behavioral Health"),
        ])
        neighborhoods = ["Bayview Hunters Point", "Chinatown", "Excelsior", "Mission", "Outer Sunset"]
        clients = []
        for n in range(1, counts["ClientCount"] + 1):
            age = 5 + (n * 17) % 84
            band = "0-17" if age < 18 else "18-34" if age < 35 else "35-49" if age < 50 else "50-64" if age < 65 else "65+"
            clients.append((n, band, "Group " + chr(65 + n % 4), neighborhoods[n % 5]))
        cls.insert("DimClientSegment", clients)
        reference = date(2026, 10, 1)
        statuses = ["completed"] * 6 + ["no_show", "no_show", "cancelled", "scheduled"]
        cls.insert("FactAppointment", [
            (n, 1 + (n * 37) % counts["ClientCount"], 1 + (n * 13) % 5,
             (reference - timedelta(days=n % 365)).isoformat(),
             (n * 11) % 16 + [2, 8, 18, 4, 25][(n * 13) % 5], statuses[n % 10])
            for n in range(1, counts["AppointmentCount"] + 1)
        ])
        statuses = ["completed"] * 4 + ["scheduled", "open", "open", "declined"]
        cls.insert("FactReferral", [
            (n, 1 + (n * 29) % counts["ClientCount"], 1 + n % 5, 1 + (n + 2) % 5,
             (reference - timedelta(days=n % 300)).isoformat(), statuses[n % 8],
             2 + (n * 7) % 40 if n % 8 < 4 else None)
            for n in range(1, counts["ReferralCount"] + 1)
        ])
        cls.insert("FactCapacity", [
            (180 * (facility - 1) + day + 1, facility,
             (reference - timedelta(days=day)).isoformat(),
             planned - (day * 7 + facility * 3) % planned,
             (day * 7 + facility * 3) % planned)
            for facility, planned in [(1, 40), (2, 55), (3, 70)]
            for day in range(180)
        ])
        views = (ROOT / "fabric" / "warehouse" / "002_privacy_views.sql").read_text()
        views = re.sub(r"(?im)^\s*GO\s*$", "", views)
        cls.connection.executescript(
            views.replace("CREATE OR ALTER VIEW", "CREATE VIEW").replace("COUNT_BIG(*)", "COUNT(*)")
        )
        cls.connection.execute("INSERT INTO reporting.CommunityHealthAccess SELECT * FROM analytics.vw_CommunityHealthAccess")
        cls.connection.execute("INSERT INTO reporting.ReferralPerformance SELECT * FROM analytics.vw_ReferralPerformance")
        cls.connection.execute("INSERT INTO reporting.Facilities SELECT * FROM analytics.DimFacility")
        cls.connection.execute("INSERT INTO reporting.Programs SELECT * FROM analytics.DimProgram")
        cls.connection.execute(
            """INSERT INTO reporting.FacilityCapacity
               SELECT c.CapacitySnapshotId,c.FacilityId,f.FacilityName,f.Neighborhood,c.SnapshotDate,
                      c.AvailableSlots,c.BookedSlots,c.BookedSlots*1.0/(c.AvailableSlots+c.BookedSlots)
               FROM analytics.FactCapacity c JOIN analytics.DimFacility f ON f.FacilityId=c.FacilityId"""
        )

    @classmethod
    def insert(cls, table: str, rows: list[tuple]) -> None:
        placeholders = ",".join("?" for _ in rows[0])
        cls.connection.executemany(f"INSERT INTO analytics.{table} VALUES ({placeholders})", rows)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.connection.close()

    def test_both_governed_tables_have_known_nonempty_totals(self) -> None:
        appointments = self.connection.execute("SELECT SUM(AppointmentCount) FROM reporting.CommunityHealthAccess").fetchone()[0]
        referrals, completed = self.connection.execute(
            "SELECT SUM(ReferralCount), SUM(CompletedReferralCount) FROM reporting.ReferralPerformance"
        ).fetchone()
        self.assertEqual(appointments, 70944)
        self.assertEqual((referrals, completed), (12000, 6000))

    def test_suppression_is_real_not_a_vacuous_empty_view_check(self) -> None:
        visible, minimum = self.connection.execute(
            "SELECT COUNT(*), MIN(AppointmentCount) FROM reporting.CommunityHealthAccess"
        ).fetchone()
        raw_count = self.connection.execute("SELECT COUNT(*) FROM analytics.FactAppointment").fetchone()[0]
        reported = self.connection.execute("SELECT SUM(AppointmentCount) FROM reporting.CommunityHealthAccess").fetchone()[0]
        self.assertEqual(visible, 5163)
        self.assertGreaterEqual(minimum, 11)
        self.assertLess(reported, raw_count)
        self.assertEqual(
            self.connection.execute("SELECT MIN(ReferralCount) FROM reporting.ReferralPerformance").fetchone()[0],
            40,
        )

    def test_ontology_keys_are_unique(self) -> None:
        for table, key in [("CommunityHealthAccess", "AccessGroupId"), ("ReferralPerformance", "ReferralGroupId")]:
            count, distinct_count = self.connection.execute(
                f"SELECT COUNT(*), COUNT(DISTINCT {key}) FROM reporting.{table}"
            ).fetchone()
            self.assertEqual(count, distinct_count)

    def test_wait_measure_is_weighted_by_appointments(self) -> None:
        model = (ROOT / "fabric" / "semantic-model" / "definition" / "tables" / "CommunityHealthAccess.tmdl").read_text()
        self.assertIn("DIVIDE(SUM(CommunityHealthAccess[WaitDaysTotal]), [Appointments])", model)
        actual = self.connection.execute(
            "WITH sample(n, total) AS (VALUES (11, 0), (99, 3960)) SELECT SUM(total)*1.0/SUM(n) FROM sample"
        ).fetchone()[0]
        self.assertEqual(actual, 36)
        total, count = self.connection.execute(
            "SELECT SUM(WaitDaysTotal), SUM(AppointmentCount) FROM reporting.CommunityHealthAccess"
        ).fetchone()
        raw_total = self.connection.execute(
            """SELECT SUM(a.WaitDays) FROM analytics.FactAppointment a
               JOIN analytics.DimProgram p ON p.ProgramId=a.ProgramId
               JOIN analytics.DimFacility f ON f.FacilityId=p.FacilityId
               JOIN analytics.DimClientSegment c ON c.ClientId=a.ClientId
               JOIN reporting.CommunityHealthAccess r ON r.ScheduledDate=a.ScheduledDate
                 AND r.ProgramId=p.ProgramId AND r.FacilityId=f.FacilityId
                 AND r.AgeBand=c.AgeBand AND r.DemographicGroup=c.DemographicGroup"""
        ).fetchone()[0]
        self.assertEqual(total, raw_total)
        self.assertGreater(count, 0)

    def test_wait_time_comparison_has_a_deliberate_visible_signal(self) -> None:
        rows = self.connection.execute(
            """SELECT ServiceCategory,SUM(WaitDaysTotal)*1.0/SUM(AppointmentCount) AS wait
               FROM reporting.CommunityHealthAccess GROUP BY ServiceCategory ORDER BY wait DESC"""
        ).fetchall()
        self.assertEqual(rows[0][0], "Behavioral Health")
        self.assertGreater(rows[0][1] - rows[-1][1], 20)

    def test_semantic_tables_bind_physical_reporting_tables(self) -> None:
        tables = ROOT / "fabric" / "semantic-model" / "definition" / "tables"
        for path in tables.glob("*.tmdl"):
            text = path.read_text()
            self.assertIn("schemaName: reporting", text)
            self.assertNotIn("entityName: analytics.", text)
            self.assertNotIn("vw_", text)

    def test_capacity_includes_demonstrable_high_utilization(self) -> None:
        rows = self.connection.execute(
            "SELECT AvailableSlots, BookedSlots FROM analytics.FactCapacity"
        ).fetchall()
        self.assertEqual(len(rows), 540)
        self.assertTrue(any(booked / (available + booked) > 0.85 for available, booked in rows))
        self.assertTrue(all(0 <= booked / (available + booked) <= 1 for available, booked in rows))

    def test_seed_and_schema_are_nondestructive_on_rerun(self) -> None:
        schema = (ROOT / "database" / "schema" / "001_oltp_schema.sql").read_text()
        seed = (ROOT / "database" / "seed" / "002_seed_synthetic.sql").read_text()
        self.assertNotIn("DROP TABLE", schema)
        self.assertEqual(len(re.findall(r"MERGE health\.", seed)), 7)
        self.assertNotIn("WHEN NOT MATCHED BY SOURCE", seed)

    def test_refresh_rolls_back_an_empty_reporting_result(self) -> None:
        refresh = (ROOT / "fabric" / "warehouse" / "003_refresh_analytics.sql").read_text()
        self.assertIn("BEGIN TRANSACTION", refresh)
        self.assertIn("ROLLBACK TRANSACTION", refresh)
        self.assertNotIn("SET XACT_ABORT", refresh)
        self.assertLess(refresh.index("THROW 51022"), refresh.index("COMMIT TRANSACTION"))
        validation = (ROOT / "fabric" / "warehouse" / "004_validate_analytics.sql").read_text()
        for table in ("CommunityHealthAccess", "ReferralPerformance", "FacilityCapacity"):
            self.assertIn(f"IF NOT EXISTS (SELECT 1 FROM reporting.{table})", validation)

    def test_demo_pulse_targets_an_existing_visible_group(self) -> None:
        before = self.connection.execute("SELECT SUM(AppointmentCount) FROM analytics.vw_CommunityHealthAccess").fetchone()[0]
        self.connection.execute("SAVEPOINT pulse")
        try:
            self.connection.execute(
                """INSERT INTO analytics.FactAppointment
                   SELECT 900001, ClientId, ProgramId, ScheduledDate, WaitDays, AppointmentStatus
                   FROM analytics.FactAppointment WHERE AppointmentId=365"""
            )
            after = self.connection.execute("SELECT SUM(AppointmentCount) FROM analytics.vw_CommunityHealthAccess").fetchone()[0]
            self.assertEqual(after, before + 1)
        finally:
            self.connection.execute("ROLLBACK TO pulse")
            self.connection.execute("RELEASE pulse")

    def test_presenter_known_answers_match_the_sql_queries(self) -> None:
        bank = json.loads((ROOT / "fabric" / "data-agent" / "evaluation_questions.json").read_text())
        self.assertEqual(len(bank["questions"]), 7)
        for question in bank["questions"]:
            with self.subTest(question=question["id"]):
                sql = question["expected_sql"]
                if "TOP (1)" in sql:
                    sql = sql.replace("TOP (1) ", "").rstrip(";") + " LIMIT 1;"
                actual = self.connection.execute(sql).fetchone()[0]
                expected = question["expected_value"]
                if isinstance(expected, str):
                    self.assertEqual(actual, expected)
                else:
                    self.assertAlmostEqual(actual, expected, delta=question["tolerance"])


if __name__ == "__main__":
    unittest.main()
