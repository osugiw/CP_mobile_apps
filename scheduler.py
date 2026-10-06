"""
scheduler.py — background aggregation jobs for Sally.

Run as a separate process alongside server_personal.py:
    python scheduler.py

Or as a systemd service (see README / deployment docs).

Environment variables (loaded from .env automatically via config.py):
    GROQ_API_KEY, DB_HOST, DB_NAME, DB_USER, DB_PASSWORD
    AGGREGATION_INTERVAL_MINUTES  — how often to run the rolling 6h summary (default 30)
    SERVER_URL                    — URL of the Flask server (default http://localhost:5000)
    SCHEDULER_TOKEN               — bearer token used to call the Flask API
"""
import os
import sys
import logging
from datetime import datetime, timedelta

import psycopg2
import requests
from apscheduler.schedulers.blocking import BlockingScheduler
from dotenv import load_dotenv

load_dotenv(os.path.join(os.path.dirname(__file__), ".env"))
load_dotenv("/home/osugiw/mcu_server/.env")

from config import (
    DB_HOST, DB_NAME, DB_USER, DB_PASSWORD,
    AGGREGATION_INTERVAL_MINUTES,
)

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [Scheduler] %(levelname)s %(message)s",
    handlers=[logging.StreamHandler(sys.stdout)],
)
log = logging.getLogger(__name__)

SERVER_URL      = os.environ.get("SERVER_URL",      "http://localhost:5000")
SCHEDULER_TOKEN = os.environ.get("SCHEDULER_TOKEN", "")

DB_CONFIG = {
    "host":     DB_HOST,
    "dbname":   DB_NAME,
    "user":     DB_USER,
    "password": DB_PASSWORD,
}

scheduler = BlockingScheduler(timezone="UTC")


def _get_active_devices() -> list[str]:
    """Return distinct device IDs that have had recordings in the last 25 hours."""
    try:
        with psycopg2.connect(**DB_CONFIG) as conn:
            with conn.cursor() as cur:
                cur.execute("""
                    SELECT DISTINCT device_id FROM recordings
                    WHERE created_at >= NOW() - INTERVAL '25 hours'
                      AND device_id IS NOT NULL;
                """)
                return [r[0] for r in cur.fetchall()]
    except Exception as exc:
        log.error("DB error fetching active devices: %s", exc)
        return []


def _trigger_window(device_id: str, window: str, until: str | None = None):
    """Call GET /summary/window on the Flask server for a given device and window."""
    params: dict = {"device_id": device_id, "window": window}
    if until:
        params["until"] = until
    headers = {"Authorization": f"Bearer {SCHEDULER_TOKEN}"}
    try:
        resp = requests.get(
            f"{SERVER_URL}/summary/window",
            params=params,
            headers=headers,
            timeout=120,
        )
        if resp.status_code == 200:
            log.info("window=%s device=%s OK", window, device_id)
        else:
            log.warning("window=%s device=%s HTTP %s: %s",
                        window, device_id, resp.status_code, resp.text[:200])
    except requests.exceptions.RequestException as exc:
        log.error("window=%s device=%s request error: %s", window, device_id, exc)


@scheduler.scheduled_job(
    "interval",
    minutes=AGGREGATION_INTERVAL_MINUTES,
    id="rolling_6h",
    jitter=60,
)
def job_rolling_6h():
    """Generate (or refresh from cache) the 6-hour rolling summary for all active devices."""
    log.info("Running rolling 6h summary job — interval=%dm", AGGREGATION_INTERVAL_MINUTES)
    for device_id in _get_active_devices():
        _trigger_window(device_id, "6h")


@scheduler.scheduled_job("cron", hour=0, minute=5, id="daily_summary", jitter=30)
def job_daily_summary():
    """
    At 00:05 UTC generate the full-day summary for yesterday.
    Uses window=day with until=yesterday 23:59:59 so the cache key is stable.
    """
    yesterday = (datetime.utcnow() - timedelta(days=1)).strftime("%Y-%m-%d")
    until_iso = f"{yesterday}T23:59:59Z"
    log.info("Running daily summary job for %s", yesterday)
    for device_id in _get_active_devices():
        _trigger_window(device_id, "day", until=until_iso)


if __name__ == "__main__":
    log.info(
        "Scheduler starting — SERVER=%s  interval=%dm",
        SERVER_URL, AGGREGATION_INTERVAL_MINUTES,
    )
    if not SCHEDULER_TOKEN:
        log.warning("SCHEDULER_TOKEN is not set — API calls will be rejected with 401")
    scheduler.start()
