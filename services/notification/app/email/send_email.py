import smtplib

from email.mime.text import MIMEText

from app.config import (
    SMTP_HOST,
    SMTP_PORT,
    SMTP_EMAIL,
    SMTP_PASSWORD,
    SMTP_SECURE
)


def send_email(
    recipient: str,
    subject: str,
    body: str
) -> bool:

    msg = MIMEText(body, "html")

    msg["Subject"] = subject
    msg["From"] = SMTP_EMAIL
    msg["To"] = recipient

    server = None

    try:

        # ======================================================
        # SSL (Port 465)
        # ======================================================

        if SMTP_SECURE:

            server = smtplib.SMTP_SSL(
                SMTP_HOST,
                SMTP_PORT,
                timeout=30
            )

        # ======================================================
        # TLS (Port 587)
        # ======================================================

        else:

            server = smtplib.SMTP(
                SMTP_HOST,
                SMTP_PORT,
                timeout=30
            )

            server.starttls()

        # ======================================================
        # LOGIN
        # ======================================================

        server.login(
            SMTP_EMAIL,
            SMTP_PASSWORD
        )

        # ======================================================
        # SEND EMAIL
        # ======================================================

        server.sendmail(
            SMTP_EMAIL,
            [recipient],
            msg.as_string()
        )

        return True

    except Exception as e:

        print(f"Email sending failed: {e}")

        return False

    finally:

        if server:

            server.quit()