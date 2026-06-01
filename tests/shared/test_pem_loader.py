from shared.security.pem_loader import load_pem, normalize_pem, verify_rsa_key_pair


def test_normalize_pem_replaces_escaped_newlines():
    escaped = "-----BEGIN RSA PRIVATE KEY-----\\nABC\\n-----END RSA PRIVATE KEY-----"
    assert "\n" in normalize_pem(escaped)
    assert "\\n" not in normalize_pem(escaped)


def test_load_pem_from_env(monkeypatch):
    monkeypatch.setenv(
        "JWT_PUBLIC_KEY",
        "-----BEGIN PUBLIC KEY-----\\nTEST\\n-----END PUBLIC KEY-----",
    )
    loaded = load_pem("JWT_PUBLIC_KEY")
    assert loaded.startswith("-----BEGIN PUBLIC KEY-----")
    assert "\nTEST\n" in loaded


def test_load_pem_from_base64_env(monkeypatch):
    import base64

    pem = "-----BEGIN PUBLIC KEY-----\nTEST\n-----END PUBLIC KEY-----"
    monkeypatch.setenv(
        "JWT_PUBLIC_KEY",
        base64.b64encode(pem.encode()).decode(),
    )
    loaded = load_pem("JWT_PUBLIC_KEY")
    assert loaded.startswith("-----BEGIN PUBLIC KEY-----")
    assert "\nTEST\n" in loaded


def test_verify_rsa_key_pair_rejects_invalid_values():
    assert verify_rsa_key_pair("", "-----BEGIN PUBLIC KEY-----\n") is False
    assert verify_rsa_key_pair("not-a-key", "not-a-key") is False
