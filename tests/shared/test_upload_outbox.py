from unittest.mock import MagicMock, patch

from shared.outbox.upload_outbox import (
    enqueue_upload_outbox,
    mark_upload_outbox_sent,
    claim_pending_upload_outbox,
)


def test_enqueue_upload_outbox_inserts_pending_document():
    collection = MagicMock()
    database = MagicMock()
    database.__getitem__.return_value = collection

    with patch("shared.outbox.upload_outbox.ensure_upload_outbox_indexes"):
        assert enqueue_upload_outbox(
            database,
            job_id="job-1",
            payload={"job_id": "job-1", "user_id": "user-1"},
        )

    collection.insert_one.assert_called_once()
    document = collection.insert_one.call_args.args[0]
    assert document["job_id"] == "job-1"
    assert document["status"] == "pending"


def test_mark_upload_outbox_sent_stores_correlation_id():
    collection = MagicMock()
    database = MagicMock()
    database.__getitem__.return_value = collection

    mark_upload_outbox_sent(database, "job-1", correlation_id="corr-123")

    update = collection.update_one.call_args.args[1]["$set"]
    assert update["status"] == "sent"
    assert update["correlation_id"] == "corr-123"


def test_claim_pending_upload_outbox_claims_matching_rows():
    collection = MagicMock()
    database = MagicMock()
    database.__getitem__.return_value = collection

    pending = {"job_id": "job-1", "status": "pending", "attempts": 0}
    claimed = {"job_id": "job-1", "status": "processing", "attempts": 1}

    cursor = MagicMock()
    cursor.sort.return_value.limit.return_value = [pending]
    collection.find.return_value = cursor
    collection.find_one_and_update.return_value = claimed

    results = claim_pending_upload_outbox(database, limit=5)

    assert results == [claimed]
