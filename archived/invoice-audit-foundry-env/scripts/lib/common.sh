#!/usr/bin/env bash
# =============================================================================
# Shared helpers for deploy.sh / teardown.sh
# =============================================================================
set -euo pipefail

# ---- logging ----------------------------------------------------------------
C_RESET="\033[0m"; C_BLUE="\033[1;34m"; C_GREEN="\033[1;32m"; C_YELLOW="\033[1;33m"; C_RED="\033[1;31m"
log()     { echo -e "${C_BLUE}[deploy]${C_RESET} $*"; }
ok()      { echo -e "${C_GREEN}[ ok ]${C_RESET} $*"; }
warn()    { echo -e "${C_YELLOW}[warn]${C_RESET} $*"; }
fail()    { echo -e "${C_RED}[fail]${C_RESET} $*" >&2; }
step()    { echo -e "\n${C_BLUE}==> $*${C_RESET}"; }

# ---- deterministic short suffix (stable across re-runs for the same RG) ----
short_suffix() {
  local seed="$1"
  echo -n "$seed" | shasum -a 256 2>/dev/null | cut -c1-6 || \
  echo -n "$seed" | sha256sum | cut -c1-6
}

# ---- access tokens ------------------------------------------------------------
arm_token() {
  az account get-access-token --scope https://management.azure.com/.default --query accessToken -o tsv
}
ai_token() {
  az account get-access-token --scope https://ai.azure.com/.default --query accessToken -o tsv
}
search_token() {
  az account get-access-token --scope https://search.azure.com/.default --query accessToken -o tsv
}

# ---- generic retry wrapper ----------------------------------------------------
# retry <timeout_seconds> <interval_seconds> <description> -- <command...>
retry() {
  local timeout="$1"; shift
  local interval="$1"; shift
  local desc="$1"; shift
  if [ "$1" = "--" ]; then shift; fi
  local waited=0
  until "$@" >/tmp/retry_out.$$ 2>&1; do
    if [ "$waited" -ge "$timeout" ]; then
      fail "Timed out after ${timeout}s waiting for: $desc"
      cat /tmp/retry_out.$$ >&2 || true
      rm -f /tmp/retry_out.$$
      return 1
    fi
    warn "$desc — not ready yet, retrying in ${interval}s (waited ${waited}s/${timeout}s)"
    sleep "$interval"
    waited=$((waited + interval))
  done
  rm -f /tmp/retry_out.$$
  ok "$desc"
}

# ---- idempotent role assignment ------------------------------------------------
# assign_role <principalId> <roleName> <scope>
assign_role() {
  local principal_id="$1" role="$2" scope="$3"
  if az role assignment list --assignee-object-id "$principal_id" --scope "$scope" \
      --query "[?roleDefinitionName=='$role'] | length(@)" -o tsv 2>/dev/null | grep -q '^[1-9]'; then
    ok "Role '$role' already assigned on $(basename "$scope")"
    return 0
  fi
  az role assignment create \
    --assignee-object-id "$principal_id" \
    --assignee-principal-type ServicePrincipal \
    --role "$role" \
    --scope "$scope" >/dev/null
  ok "Assigned role '$role' on $(basename "$scope")"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { fail "Required command '$1' not found in PATH."; exit 1; }
}
