import os
from unittest.mock import patch

import httpx

from shared.http.internal_client import internal_http_client


def test_internal_http_client_uses_ca_bundle_when_present(tmp_path):
    ca_file = tmp_path / "ca.crt"
    ca_file.write_text("test-ca", encoding="utf-8")

    with patch.dict(os.environ, {"INTERNAL_TLS_CA_PATH": str(ca_file)}, clear=False):
        with patch.object(httpx, "AsyncClient") as mock_client:
            internal_http_client(timeout=15.0)
            mock_client.assert_called_once_with(
                timeout=15.0,
                verify=str(ca_file),
            )


def test_internal_http_client_defaults_to_system_trust_store(tmp_path):
    missing_ca = tmp_path / "missing.crt"

    with patch.dict(os.environ, {"INTERNAL_TLS_CA_PATH": str(missing_ca)}, clear=False):
        with patch.object(httpx, "AsyncClient") as mock_client:
            internal_http_client()
            mock_client.assert_called_once_with(timeout=30.0, verify=True)
