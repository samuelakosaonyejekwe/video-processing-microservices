import sys
from pathlib import Path


def ensure_shared_path() -> None:
    service_root = Path(__file__).resolve().parent.parent
    for root in (service_root, service_root.parent, service_root.parent.parent):
        if (root / "shared").is_dir() and str(root) not in sys.path:
            sys.path.insert(0, str(root))
            return
