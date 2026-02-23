#!/usr/bin/env bash
set -euo pipefail

BUNDLE_ID="${LUNARDISK_BUNDLE_ID:-com.lunardisk.app}"

declare -a scopes=()

if [[ $# -gt 0 ]]; then
  scopes=("$@")
elif [[ -n "${RESET_STATE:-}" ]]; then
  IFS=',' read -r -a scopes <<< "$RESET_STATE"
elif [[ -n "${LUNARDISK_RESET_STATE:-}" ]]; then
  IFS=',' read -r -a scopes <<< "$LUNARDISK_RESET_STATE"
else
  scopes=("onboarding")
fi

reset_onboarding() {
  defaults delete "$BUNDLE_ID" "hasCompletedOnboarding" >/dev/null 2>&1 || true
}

reset_all() {
  defaults delete "$BUNDLE_ID" >/dev/null 2>&1 || true
}

for entry in "${scopes[@]}"; do
  IFS=',' read -r -a split_scopes <<< "$entry"
  for raw_scope in "${split_scopes[@]}"; do
    scope="$(echo "$raw_scope" | tr '[:upper:]' '[:lower:]' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"

    case "$scope" in
      onboarding)
        reset_onboarding
        ;;
      all)
        reset_all
        ;;
      "")
        ;;
      *)
        echo "warning: unknown reset scope '$raw_scope' (supported: onboarding, all)" >&2
        ;;
    esac
  done
done

echo "Reset complete for bundle '$BUNDLE_ID' with scopes: ${scopes[*]}"
