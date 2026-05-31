from app import config


def test_notification_config_defaults():
    assert config.APP_NAME
    assert config.APP_PORT > 0
    assert isinstance(config.CORS_ALLOWED_ORIGINS, list)
