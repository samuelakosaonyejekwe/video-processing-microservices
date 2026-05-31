from unittest.mock import Mock

from shared.http.upstream_errors import upstream_error_detail


def test_upstream_error_detail_reads_detail_field():
    response = Mock()
    response.json.return_value = {"detail": "Invalid credentials"}
    assert upstream_error_detail(response, "default") == "Invalid credentials"


def test_upstream_error_detail_reads_nested_error_message():
    response = Mock()
    response.json.return_value = {
        "error": {"code": "HTTP_401", "message": "Invalid credentials"}
    }
    assert upstream_error_detail(response, "default") == "Invalid credentials"


def test_upstream_error_detail_falls_back_to_default():
    response = Mock()
    response.json.return_value = {}
    assert upstream_error_detail(response, "Login failed") == "Login failed"


def test_upstream_error_detail_uses_response_text_when_not_json():
    response = Mock()
    response.json.side_effect = ValueError("not json")
    response.text = "upstream unavailable"
    assert upstream_error_detail(response, "default") == "upstream unavailable"
