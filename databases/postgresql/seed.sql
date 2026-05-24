INSERT INTO users (
    username,
    email,
    password
)
VALUES (
    'admin',
    'admin@example.com',
    'password123'
);


INSERT INTO conversions (
    user_id,
    original_filename,
    converted_filename,
    status
)
VALUES (
    1,
    'sample-video.mp4',
    'sample-video.mp3',
    'completed'
);