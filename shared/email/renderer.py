from pathlib import Path


def render_email_template(template_name: str, **context: str) -> str:
    template_path = Path(__file__).parent / "templates" / template_name
    content = template_path.read_text(encoding="utf-8")

    for key, value in context.items():
        content = content.replace(f"{{{{{key}}}}}", str(value))

    return content
