import requests

API_BASE = "http://<RASPBERRY_PI_IP>:5000"


def get_intents(device_id: str, intent_type: str | None = None, include_transcript: bool = False, include_summary: bool = False) -> list:
    params = {"device_id": device_id}
    if intent_type:
        params["type"] = intent_type
    if include_transcript:
        params["include_transcript"] = "true"
    if include_summary:
        params["include_summary"] = "true"
    response = requests.get(f"{API_BASE}/intents", params=params, timeout=10)
    response.raise_for_status()
    return response.json()


def get_pending_reminders(device_id: str) -> list:
    params = {"device_id": device_id}
    response = requests.get(f"{API_BASE}/reminders/pending", params=params, timeout=10)
    response.raise_for_status()
    return response.json()


def mark_reminder_sent(intent_id: int) -> dict:
    response = requests.post(f"{API_BASE}/reminders/{intent_id}/sent", timeout=10)
    response.raise_for_status()
    return response.json()


if __name__ == "__main__":
    device_id = input("Device ID: ").strip()
    print("\nFetching intents with transcript and summary...")
    try:
        intents = get_intents(device_id, include_transcript=True, include_summary=True)
        print(f"Found {len(intents)} intent(s):")
        for intent in intents:
            print(f"- [{intent['id']}] {intent['task']} ({intent['intent_type']}) -> {intent['decision']} at {intent['scheduled_time']}")
            print(f"  transcript={repr(intent.get('transcript'))[:120]}")
            print(f"  summary={repr(intent.get('summary'))[:120]}")
    except Exception as exc:
        print(f"Error fetching intents: {exc}")

    print("\nFetching pending reminders...")
    try:
        reminders = get_pending_reminders(device_id)
        print(f"Found {len(reminders)} pending reminder(s):")
        for rem in reminders:
            print(f"- [{rem['id']}] {rem['task']} ({rem['intent_type']}) scheduled: {rem['scheduled_time']}")
    except Exception as exc:
        print(f"Error fetching reminders: {exc}")
