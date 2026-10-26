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

log "Deleting resource group '$RESOURCE_GROUP' (waiting for completion so the Foundry account can be purged)..."
az group delete -n "$RESOURCE_GROUP" --yes
ok "Resource group deleted."

# Cognitive Services accounts (the Foundry account) are soft-deleted by Azure for a
# retention period even after the resource group is gone. Purge it immediately so a
# future deploy.sh run against the same FOUNDRY_ACCOUNT_NAME doesn't need to wait out
# the retention window (deploy.sh also self-heals this, but purging here is faster).
if az cognitiveservices account list-deleted --query "[?name=='$FOUNDRY_ACCOUNT_NAME']" -o tsv 2>/dev/null | grep -q "$FOUNDRY_ACCOUNT_NAME"; then
  log "Purging soft-deleted Foundry account '$FOUNDRY_ACCOUNT_NAME'..."
  az cognitiveservices account purge -n "$FOUNDRY_ACCOUNT_NAME" -g "$RESOURCE_GROUP" -l "$LOCATION" >/dev/null 2>&1 || true
  ok "Purged."
fi
ok "Teardown complete. No billable resources remain from this demo."
