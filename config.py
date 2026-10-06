"""
config.py — centralised configuration via environment variables.

On the Pi, create /home/osugiw/mcu_server/.env with:
    GROQ_API_KEY=gsk_...
    DB_PASSWORD=...
    (optionally override any variable below)

server_personal.py loads that file via python-dotenv before importing this module.
"""
import os

# ── Groq API ──────────────────────────────────────────────────────────────────
GROQ_API_KEY = os.environ.get("GROQ_API_KEY", "")

# ── PostgreSQL ────────────────────────────────────────────────────────────────
DB_HOST     = os.environ.get("DB_HOST",     "localhost")
DB_NAME     = os.environ.get("DB_NAME",     "stt_db")
DB_USER     = os.environ.get("DB_USER",     "jeeven")
DB_PASSWORD = os.environ.get("DB_PASSWORD", "")

# ── File paths ────────────────────────────────────────────────────────────────
_BASE = os.environ.get("MCU_SERVER_DIR", "/home/osugiw/mcu_server")

AUDIO_FOLDER      = os.environ.get("AUDIO_FOLDER",      os.path.join(_BASE, "uploads"))
TRANSCRIPT_FOLDER = os.environ.get("TRANSCRIPT_FOLDER", os.path.join(_BASE, "transcripts"))
SUMMARY_FOLDER    = os.environ.get("SUMMARY_FOLDER",    os.path.join(_BASE, "summaries"))
ENROLL_FOLDER     = os.environ.get("ENROLL_FOLDER",     os.path.join(_BASE, "enrollments"))
KEY_FILE          = os.environ.get("KEY_FILE",          os.path.join(_BASE, ".encryption_key"))

# ── Scheduler ─────────────────────────────────────────────────────────────────
AGGREGATION_INTERVAL_MINUTES = int(os.environ.get("AGGREGATION_INTERVAL_MINUTES", "30"))

# ── Retention ─────────────────────────────────────────────────────────────────
RETENTION_TRANSCRIPT_DAYS = int(os.environ.get("RETENTION_TRANSCRIPT_DAYS", "90"))
RETENTION_AUDIO_DAYS      = int(os.environ.get("RETENTION_AUDIO_DAYS",      "7"))
