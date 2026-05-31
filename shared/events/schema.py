from datetime import datetime, timezone
import uuid


def build_event(event_type: str, payload: dict, correlation_id: str | None = None) -> dict:
    return {
        "event_id": str(uuid.uuid4()),
        "event_type": event_type,
        "correlation_id": correlation_id or str(uuid.uuid4()),
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "payload": payload,
    }
