required_fields = ["event_id", "event_type", "timestamp", "payload"]


def validate_event(event):

    for field in required_fields:

        if field not in event:

            raise ValueError(f"Missing event field: {field}")
