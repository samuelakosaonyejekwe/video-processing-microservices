import html
from pathlib import Path

_TEMPLATE_DIR = (Path(__file__).parent / "templates").resolve()


def render_email_template(template_name: str, **context: str) -> str:
    # Resolve and confine the template path to the templates directory so a
    # crafted template_name cannot traverse out of it.
    template_path = (_TEMPLATE_DIR / template_name).resolve()
    if not template_path.is_relative_to(_TEMPLATE_DIR):
        raise ValueError(f"Invalid template name: {template_name}")

    content = template_path.read_text(encoding="utf-8")

    # HTML-escape substituted values: they can include user-controlled data
    # (e.g. filenames), and these are HTML email templates.
    for key, value in context.items():
        content = content.replace(f"{{{{{key}}}}}", html.escape(str(value)))

    return content
