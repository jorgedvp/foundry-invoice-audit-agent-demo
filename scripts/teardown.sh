#!/usr/bin/env bash
# =============================================================================
# teardown.sh — Delete everything the demo deployed, in one shot.
#
# Because every resource created by deploy.sh lives inside a single resource
# group, teardown is a single resource-group deletion — no need to track
# individual resource names.
#
# Usage:
#   ./scripts/teardown.sh config.env
#   ./scripts/teardown.sh config.env --yes     # skip the confirmation prompt
# =============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

CONFIG_FILE="${1:-$REPO_ROOT/config.env}"
AUTO_YES="${2:-}"
if [ ! -f "$CONFIG_FILE" ]; then
  fail "Config file not found: $CONFIG_FILE"
  exit 1
fi
# shellcheck disable=SC1090
source "$CONFIG_FILE"

require_cmd az

az account show >/dev/null 2>&1 || az login --tenant "$AZURE_TENANT_ID"
az account set --subscription "$AZURE_SUBSCRIPTION_ID"

if ! az group show -n "$RESOURCE_GROUP" >/dev/null 2>&1; then
  ok "Resource group '$RESOURCE_GROUP' doesn't exist — nothing to tear down."
  exit 0
fi

step "This will permanently delete resource group '$RESOURCE_GROUP' and everything in it:"
az resource list -g "$RESOURCE_GROUP" --query "[].{Name:name, Type:type}" -o table

if [ "$AUTO_YES" != "--yes" ]; then
  read -r -p "Type the resource group name to confirm deletion: " confirm
  if [ "$confirm" != "$RESOURCE_GROUP" ]; then
    fail "Confirmation did not match. Aborting — nothing was deleted."
    exit 1
  fi
fi

log "Deleting resource group '$RESOURCE_GROUP' (running in the background; this can take a few minutes)..."
az group delete -n "$RESOURCE_GROUP" --yes --no-wait
ok "Deletion started. Check progress with: az group show -n $RESOURCE_GROUP (returns an error once fully deleted)"
