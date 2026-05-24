import smtplib
from email.mime.text import MIMEText
from app.config import (
    SMTP_HOST,
    SMTP_PORT,
    SMTP_USERNAME,
    SMTP_PASSWORD
)


def send_email(
    recipient: str,
    subject: str,
    body: str
):

    msg = MIMEText(body, "html")

    msg["Subject"] = subject
    msg["From"] = SMTP_USERNAME
    msg["To"] = recipient

    server = smtplib.SMTP(
        SMTP_HOST,
        SMTP_PORT
    )

    server.starttls()

    server.login(
        SMTP_USERNAME,
        SMTP_PASSWORD
    )

    server.sendmail(
        SMTP_USERNAME,
        [recipient],
        msg.as_string()
    )

    server.quit()

    return True