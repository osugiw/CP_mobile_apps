"""
test_db.py — unit tests for DB model operations.

Requires a running PostgreSQL instance with a test database.
Set env vars before running:
    DB_NAME=stt_db_test DB_USER=jeeven DB_PASSWORD=... pytest tests/test_db.py -v
"""
import os
import json
import pytest
import psycopg2
from datetime import datetime, timedelta

DB_CONFIG = {
    "host":     os.environ.get("DB_HOST",     "localhost"),
    "dbname":   os.environ.get("DB_NAME",     "stt_db"),
    "user":     os.environ.get("DB_USER",     "jeeven"),
    "password": os.environ.get("DB_PASSWORD", "12345"),
}


def get_conn():
    return psycopg2.connect(**DB_CONFIG)


class TestRecordings:
    def test_insert_recording(self):
        with get_conn() as conn:
            with conn.cursor() as cur:
                cur.execute(
                    "INSERT INTO recordings (audio_file, status, device_id) "
                    "VALUES (%s,%s,%s) RETURNING id;",
                    ("/tmp/test.wav", "uploaded", "test_device"),
                )
                rec_id = cur.fetchone()[0]
            conn.rollback()
        assert isinstance(rec_id, int) and rec_id > 0

    def test_update_status(self):
        with get_conn() as conn:
            with conn.cursor() as cur:
                cur.execute(
                    "INSERT INTO recordings (audio_file, status, device_id) "
                    "VALUES (%s,%s,%s) RETURNING id;",
                    ("/tmp/test2.wav", "uploaded", "test_device"),
                )
                rec_id = cur.fetchone()[0]
                cur.execute("UPDATE recordings SET status=%s WHERE id=%s;",
                            ("transcribed", rec_id))
                cur.execute("SELECT status FROM recordings WHERE id=%s;", (rec_id,))
                assert cur.fetchone()[0] == "transcribed"
            conn.rollback()


class TestTranscripts:
    def test_insert_transcript(self):
        with get_conn() as conn:
            with conn.cursor() as cur:
                cur.execute(
                    "INSERT INTO recordings (audio_file, status, device_id) "
                    "VALUES (%s,%s,%s) RETURNING id;",
                    ("/tmp/t.wav", "uploaded", "test_device"),
                )
                rec_id = cur.fetchone()[0]
                cur.execute(
                    "INSERT INTO transcripts (recording_id, text, device_id) "
                    "VALUES (%s,%s,%s) RETURNING id;",
                    (rec_id, "/tmp/t.txt.enc", "test_device"),
                )
                t_id = cur.fetchone()[0]
            conn.rollback()
        assert t_id > 0


class TestIntents:
    def test_insert_intent(self):
        with get_conn() as conn:
            with conn.cursor() as cur:
                cur.execute(
                    "INSERT INTO recordings (audio_file, status, device_id) "
                    "VALUES (%s,%s,%s) RETURNING id;",
                    ("/tmp/i.wav", "uploaded", "test_device"),
                )
                rec_id = cur.fetchone()[0]
                cur.execute("""
                    INSERT INTO intents
                      (recording_id, device_id, task, intent_type, fused_confidence,
                       decision, action, status)
                    VALUES (%s,%s,%s,%s,%s,%s,%s,%s)
                    RETURNING id;
                """, (rec_id, "test_device", "Call the doctor", "appointment",
                      0.85, "act", "notify", "pending"))
                intent_id = cur.fetchone()[0]
            conn.rollback()
        assert intent_id > 0


class TestWindowSummaries:
    def test_upsert_window_summary(self):
        now   = datetime.utcnow()
        start = now - timedelta(hours=6)
        payload = {"headline": "test headline", "summary": "test body"}

        with get_conn() as conn:
            with conn.cursor() as cur:
                cur.execute("""
                    INSERT INTO window_summaries
                      (device_id, window_type, window_start, window_end, summary_json)
                    VALUES (%s,%s,%s,%s,%s)
                    ON CONFLICT (device_id, window_type, window_start)
                    DO UPDATE SET summary_json = EXCLUDED.summary_json, updated_at = NOW()
                    RETURNING id;
                """, ("test_dev", "6h", start, now, json.dumps(payload)))
                ws_id = cur.fetchone()[0]
            conn.rollback()
        assert ws_id > 0

    def test_idempotent_upsert(self):
        now   = datetime.utcnow().replace(microsecond=0)
        start = now - timedelta(hours=6)
        payload_v1 = {"headline": "first"}
        payload_v2 = {"headline": "second"}

        with get_conn() as conn:
            with conn.cursor() as cur:
                for payload in (payload_v1, payload_v2):
                    cur.execute("""
                        INSERT INTO window_summaries
                          (device_id, window_type, window_start, window_end, summary_json)
                        VALUES (%s,%s,%s,%s,%s)
                        ON CONFLICT (device_id, window_type, window_start)
                        DO UPDATE SET summary_json = EXCLUDED.summary_json, updated_at = NOW()
                        RETURNING id;
                    """, ("idem_dev", "6h", start, now, json.dumps(payload)))
                    row_id = cur.fetchone()[0]
                # Only one row should exist
                cur.execute(
                    "SELECT COUNT(*), summary_json->>'headline' FROM window_summaries "
                    "WHERE device_id='idem_dev' AND window_type='6h' AND window_start=%s;",
                    (start,),
                )
                count, headline = cur.fetchone()
                assert count == 1
                assert headline == "second"
            conn.rollback()


class TestReminders:
    def test_create_reminder(self):
        with get_conn() as conn:
            with conn.cursor() as cur:
                cur.execute("""
                    INSERT INTO reminders (device_id, title, status)
                    VALUES (%s,%s,%s) RETURNING id;
                """, ("test_dev", "Test reminder", "pending"))
                r_id = cur.fetchone()[0]
            conn.rollback()
        assert r_id > 0

    def test_update_status(self):
        with get_conn() as conn:
            with conn.cursor() as cur:
                cur.execute("""
                    INSERT INTO reminders (device_id, title, status)
                    VALUES (%s,%s,%s) RETURNING id;
                """, ("test_dev", "Update me", "pending"))
                r_id = cur.fetchone()[0]
                cur.execute(
                    "UPDATE reminders SET status='resolved' WHERE id=%s;", (r_id,)
                )
                cur.execute("SELECT status FROM reminders WHERE id=%s;", (r_id,))
                assert cur.fetchone()[0] == "resolved"
            conn.rollback()

    def test_delete_reminder(self):
        with get_conn() as conn:
            with conn.cursor() as cur:
                cur.execute("""
                    INSERT INTO reminders (device_id, title, status)
                    VALUES (%s,%s,%s) RETURNING id;
                """, ("test_dev", "Delete me", "pending"))
                r_id = cur.fetchone()[0]
                cur.execute("DELETE FROM reminders WHERE id=%s RETURNING id;", (r_id,))
                assert cur.fetchone()[0] == r_id
            conn.rollback()
