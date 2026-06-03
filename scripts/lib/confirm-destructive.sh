#!/bin/bash
# Shared confirmation guard for destructive operations (terraform destroy,
# PVC-data-losing teardown, etc.).
#
# Usage:
#   source scripts/lib/confirm-destructive.sh
#   confirm_destructive "destroy the EKS cluster (PVC data will be lost)"
#
# Behaviour:
#   - Interactive TTY: prompts the operator to type 'yes' to proceed.
#   - Non-interactive (CI): proceeds only when CONFIRM_DESTROY=yes is set,
#     or when "--yes"/"-y" was passed on the calling script's argv (exported
#     by the caller as CONFIRM_DESTROY=yes), otherwise aborts.
# Returns 0 to proceed; calls exit 1 to abort.

confirm_destructive() {
  local action="${1:-perform a destructive operation}"

  # Explicit opt-in via env flag (CI usability).
  case "${CONFIRM_DESTROY:-}" in
    yes|YES|y|Y|true|TRUE|1)
      echo "CONFIRM_DESTROY set — proceeding to ${action}." >&2
      return 0
      ;;
  esac

  if [ -t 0 ]; then
    local reply=""
    echo "About to ${action}." >&2
    echo "This is destructive and may be irreversible." >&2
    printf "Type 'yes' to continue: " >&2
    read -r reply
    if [ "${reply}" = "yes" ]; then
      return 0
    fi
    echo "Aborted: confirmation not given." >&2
    exit 1
  fi

  # Non-interactive and no env flag — fail closed.
  echo "ERROR: refusing to ${action} non-interactively." >&2
  echo "Set CONFIRM_DESTROY=yes (or pass --yes) to proceed." >&2
  exit 1
}
