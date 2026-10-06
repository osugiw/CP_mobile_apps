"""
test_api.py — integration tests against the running Flask server.

Requires:
  - Server running on localhost:5000 (python server_personal.py)
  - A valid API token set in env var TEST_API_TOKEN
  - A device ID set in env var TEST_DEVICE_ID (default: test_device_pytest)

Run:
    TEST_API_TOKEN=<token> pytest tests/test_api.py -v
"""
import os
import pytest
import requests

BASE      = os.environ.get("TEST_SERVER_URL", "http://localhost:5000")
TOKEN     = os.environ.get("TEST_API_TOKEN", "")
DEVICE    = os.environ.get("TEST_DEVICE_ID", "test_device_pytest")
HEADERS   = {"Authorization": f"Bearer {TOKEN}", "Content-Type": "application/json"}


# ── helpers ───────────────────────────────────────────────────────────────────

def get(path, params=None, auth=True):
    h = HEADERS if auth else {}
    return requests.get(f"{BASE}{path}", params=params, headers=h, timeout=30)

def post(path, json=None, auth=True):
    h = HEADERS if auth else {}
    return requests.post(f"{BASE}{path}", json=json, headers=h, timeout=30)

def patch(path, json=None):
    return requests.patch(f"{BASE}{path}", json=json, headers=HEADERS, timeout=30)

def delete(path):
    return requests.delete(f"{BASE}{path}", headers=HEADERS, timeout=30)


# ── basic health ──────────────────────────────────────────────────────────────

class TestHealth:
    def test_root_no_auth(self):
        r = get("/", auth=False)
        assert r.status_code == 200
        assert "Sally" in r.text


# ── auth enforcement ──────────────────────────────────────────────────────────

class TestAuth:
    def test_summary_window_rejects_no_token(self):
        r = get("/summary/window", params={"device_id": DEVICE, "window": "6h"}, auth=False)
        assert r.status_code == 401

    def test_reminders_rejects_no_token(self):
        r = get("/reminders", params={"device_id": DEVICE}, auth=False)
        assert r.status_code == 401

    def test_intents_rejects_no_token(self):
        r = get("/intents", params={"device_id": DEVICE}, auth=False)
        assert r.status_code == 401

    @pytest.mark.skipif(not TOKEN, reason="TEST_API_TOKEN not set")
    def test_valid_token_accepted(self):
        r = get("/intents", params={"device_id": DEVICE})
        assert r.status_code == 200


# ── summary/window ────────────────────────────────────────────────────────────

@pytest.mark.skipif(not TOKEN, reason="TEST_API_TOKEN not set")
class TestSummaryWindow:
    def test_6h_returns_200(self):
        r = get("/summary/window", params={"device_id": DEVICE, "window": "6h"})
        assert r.status_code == 200
        data = r.json()
        assert data["window_type"] == "6h"
        assert "summary" in data
        assert "intents" in data

    def test_day_returns_200(self):
        r = get("/summary/window", params={"device_id": DEVICE, "window": "day"})
        assert r.status_code == 200
        data = r.json()
        assert data["window_type"] == "day"

    def test_24h_returns_200(self):
        r = get("/summary/window", params={"device_id": DEVICE, "window": "24h"})
        assert r.status_code == 200

    def test_invalid_window_returns_400(self):
        r = get("/summary/window", params={"device_id": DEVICE, "window": "1h"})
        assert r.status_code == 400

    def test_missing_device_id_returns_400(self):
        r = get("/summary/window", params={"window": "6h"})
        assert r.status_code == 400

    def test_cache_hit_on_second_call(self):
        params = {"device_id": DEVICE, "window": "6h"}
        r1 = get("/summary/window", params=params)
        r2 = get("/summary/window", params=params)
        assert r1.status_code == r2.status_code == 200
        # Both should return the same generated_at (cache hit)
        assert r1.json()["generated_at"] == r2.json()["generated_at"]


# ── reminders CRUD ────────────────────────────────────────────────────────────

@pytest.mark.skipif(not TOKEN, reason="TEST_API_TOKEN not set")
class TestRemindersCRUD:
    def test_create_reminder(self):
        r = post("/reminders", json={
            "device_id": DEVICE,
            "title":     "pytest: test reminder",
            "notes":     "created by automated test",
        })
        assert r.status_code == 201
        data = r.json()
        assert data["title"] == "pytest: test reminder"
        assert data["status"] == "pending"
        assert "id" in data
        return data["id"]

    def test_list_reminders(self):
        # Create one first
        post("/reminders", json={"device_id": DEVICE, "title": "list test"})
        r = get("/reminders", params={"device_id": DEVICE, "status": "pending"})
        assert r.status_code == 200
        assert isinstance(r.json(), list)

    def test_update_reminder_status(self):
        created = post("/reminders", json={
            "device_id": DEVICE, "title": "resolve me"
        }).json()
        rid = created["id"]
        r = patch(f"/reminders/{rid}", json={"status": "resolved"})
        assert r.status_code == 200

    def test_delete_reminder(self):
        created = post("/reminders", json={
            "device_id": DEVICE, "title": "delete me"
        }).json()
        rid = created["id"]
        r = delete(f"/reminders/{rid}")
        assert r.status_code == 200
        # Confirm it's gone
        r2 = delete(f"/reminders/{rid}")
        assert r2.status_code == 404

    def test_create_reminder_missing_title_returns_400(self):
        r = post("/reminders", json={"device_id": DEVICE})
        assert r.status_code == 400

    def test_update_invalid_status_returns_400(self):
        created = post("/reminders", json={
            "device_id": DEVICE, "title": "status test"
        }).json()
        rid = created["id"]
        r = patch(f"/reminders/{rid}", json={"status": "invalid_status"})
        assert r.status_code == 400
        # Cleanup
        delete(f"/reminders/{rid}")

    def test_full_lifecycle(self):
        # Create → list → update → delete
        r_create = post("/reminders", json={
            "device_id":    DEVICE,
            "title":        "full lifecycle test",
            "notes":        "integration test",
            "repeat_rule":  "none",
        })
        assert r_create.status_code == 201
        rid = r_create.json()["id"]

        r_list = get("/reminders", params={"device_id": DEVICE, "status": "all"})
        assert any(x["id"] == rid for x in r_list.json())

        r_patch = patch(f"/reminders/{rid}", json={"status": "resolved"})
        assert r_patch.status_code == 200

        r_del = delete(f"/reminders/{rid}")
        assert r_del.status_code == 200
