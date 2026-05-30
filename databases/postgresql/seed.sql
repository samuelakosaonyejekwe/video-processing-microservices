INSERT INTO users (
    username,
    email,
    password
)
VALUES (
    ${APP_ADMIN_USERNAME},
    ${APP_ADMIN_EMAIL},
    ${APP_ADMIN_PASSWORD_HASH}
);


INSERT INTO conversions (
    user_id,
    original_filename,
    converted_filename,
    status
)
VALUES (
    ${DEFAULT_USER_ID},
    ${SAMPLE_VIDEO_FILENAME},
    ${SAMPLE_AUDIO_FILENAME},
    'completed'
);