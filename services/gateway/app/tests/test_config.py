import os


def test_jwt_public_key_loaded_from_env(monkeypatch):
    monkeypatch.setenv("APP_ENV", "production")
    monkeypatch.setenv("FRONTEND_URL", "https://example.com")
    monkeypatch.setenv(
        "JWT_PUBLIC_KEY",
        "-----BEGIN PUBLIC KEY-----\\nMIIB\\n-----END PUBLIC KEY-----",
    )

    from importlib import reload

    import app.config as config

    reload(config)

    assert config.JWT_PUBLIC_KEY.startswith("-----BEGIN PUBLIC KEY-----")
    assert "\n" in config.JWT_PUBLIC_KEY
