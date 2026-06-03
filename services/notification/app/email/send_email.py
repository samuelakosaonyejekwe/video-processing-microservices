import logging
import re
import smtplib

from email.mime.text import MIMEText

from app.config import (
    SMTP_HOST,
    SMTP_PORT,
    SMTP_EMAIL,
    SMTP_PASSWORD,
    SMTP_SECURE,
    EMAIL_ENABLED,
)

logger = logging.getLogger(__name__)

_EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")


def send_email(recipient: str, subject: str, body: str) -> bool:

    # Reject anything that isn't a clean single email address. A CR/LF in the
    # recipient would otherwise enable SMTP header injection.
    if not recipient or not _EMAIL_RE.match(recipient.strip()):
        logger.error("Refusing to send email to invalid recipient")
        return False
    recipient = recipient.strip()

    # A CR/LF in the subject would otherwise enable SMTP header injection, the
    # same way it would in the recipient. Reject any control characters.
    if subject is None or "\r" in subject or "\n" in subject:
        logger.error("Refusing to send email with invalid subject header")
        return False

    if not EMAIL_ENABLED:
        logger.info(
            "Email disabled (EMAIL_ENABLED=false) — skipping send to %s", recipient
        )
        return True

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

            server = smtplib.SMTP_SSL(SMTP_HOST, SMTP_PORT, timeout=30)

        # ======================================================
        # TLS (Port 587)
        # ======================================================

        else:

            server = smtplib.SMTP(SMTP_HOST, SMTP_PORT, timeout=30)

            server.starttls()

        # ======================================================
        # LOGIN
        # ======================================================

        server.login(SMTP_EMAIL, SMTP_PASSWORD)

        # ======================================================
        # SEND EMAIL
        # ======================================================

        server.sendmail(SMTP_EMAIL, [recipient], msg.as_string())

        return True

    except Exception as e:

        logger.error("Email sending failed: %s", e)

        return False

    finally:

        if server:

            server.quit()
