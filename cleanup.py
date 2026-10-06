"""
cleanup.py — data retention and disk space management.

Run daily via cron:
    0 2 * * * /usr/bin/python3 /home/osugiw/mcu_server/cleanup.py >> /var/log/sally-cleanup.log 2>&1

Behaviour (controlled via environment variables):
    RETENTION_AUDIO_DAYS      — delete encrypted audio files older than N days (default 7)
    RETENTION_TRANSCRIPT_DAYS — delete encrypted transcript/summary files and their
                                 memory_chunk rows older than N days (default 90)
                                 DB rows for recordings/transcripts/summaries are kept
                                 indefinitely (they are small); only the encrypted files
                                 on disk are removed.
"""
import os
import sys
import logging
from datetime import datetime, timedelta

import psycopg2
from dotenv import load_dotenv

load_dotenv(os.path.join(os.path.dirname(__file__), ".env"))
load_dotenv("/home/osugiw/mcu_server/.env")

from config import (
    DB_HOST, DB_NAME, DB_USER, DB_PASSWORD,
    RETENTION_AUDIO_DAYS, RETENTION_TRANSCRIPT_DAYS,
)

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [Cleanup] %(message)s",
    handlers=[logging.StreamHandler(sys.stdout)],
)
log = logging.getLogger(__name__)

DB_CONFIG = {
    "host":     DB_HOST,
    "dbname":   DB_NAME,
    "user":     DB_USER,
    "password": DB_PASSWORD,
}


def _safe_remove(path: str) -> bool:
    if path and os.path.exists(path):
        try:
            os.remove(path)
            return True
        except OSError as exc:
            log.warning("Could not remove %s: %s", path, exc)
    return False


def purge_old_audio():
    cutoff = datetime.utcnow() - timedelta(days=RETENTION_AUDIO_DAYS)
    log.info("Purging audio files older than %s (cutoff=%s)", RETENTION_AUDIO_DAYS, cutoff.date())
    removed = 0
    with psycopg2.connect(**DB_CONFIG) as conn:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT id, audio_file FROM recordings WHERE created_at < %s AND audio_file IS NOT NULL;",
                (cutoff,),
            )
            rows = cur.fetchall()
            for rec_id, path in rows:
                # Try both raw path and .enc variant
                for candidate in (path, path + ".enc" if not path.endswith(".enc") else path):
                    if _safe_remove(candidate):
                        removed += 1
                        break
            # Null out the path so we don't try again
            cur.execute(
                "UPDATE recordings SET audio_file = NULL WHERE created_at < %s AND audio_file IS NOT NULL;",
                (cutoff,),
            )
    log.info("Audio purge complete — %d file(s) removed", removed)


def purge_old_transcripts():
    cutoff = datetime.utcnow() - timedelta(days=RETENTION_TRANSCRIPT_DAYS)
    log.info(
        "Purging transcript/summary files older than %s days (cutoff=%s)",
        RETENTION_TRANSCRIPT_DAYS, cutoff.date(),
    )
    removed = 0
    with psycopg2.connect(**DB_CONFIG) as conn:
        with conn.cursor() as cur:
            # Remove transcript .enc files
            cur.execute(
                "SELECT t.id, t.text FROM transcripts t "
                "JOIN recordings r ON r.id = t.recording_id "
                "WHERE r.created_at < %s AND t.text IS NOT NULL;",
                (cutoff,),
            )
            for t_id, path in cur.fetchall():
                if _safe_remove(path):
                    removed += 1

            # Remove summary .enc files
            cur.execute(
                "SELECT s.id, s.summary FROM summaries s "
                "JOIN recordings r ON r.id = s.recording_id "
                "WHERE r.created_at < %s AND s.summary IS NOT NULL;",
                (cutoff,),
            )
            for s_id, path in cur.fetchall():
                if _safe_remove(path):
                    removed += 1

            # Purge memory_chunks (plaintext content — these are large in aggregate)
            cur.execute(
                "DELETE FROM memory_chunks mc "
                "USING recordings r "
                "WHERE mc.recording_id = r.id AND r.created_at < %s;",
                (cutoff,),
            )
            chunks_deleted = cur.rowcount

    log.info(
        "Transcript/summary purge complete — %d file(s) removed, %d memory chunks deleted",
        removed, chunks_deleted,
    )


def vacuum_db():
    """Run VACUUM ANALYZE to reclaim space after bulk deletes."""
    log.info("Running VACUUM ANALYZE...")
    conn = psycopg2.connect(**DB_CONFIG)
    conn.autocommit = True
    with conn.cursor() as cur:
        cur.execute("VACUUM ANALYZE;")
    conn.close()
    log.info("VACUUM ANALYZE complete.")


if __name__ == "__main__":
    log.info("=== Sally cleanup starting at %s ===", datetime.utcnow().isoformat())
    purge_old_audio()
    purge_old_transcripts()
    vacuum_db()
    log.info("=== Cleanup finished ===")
