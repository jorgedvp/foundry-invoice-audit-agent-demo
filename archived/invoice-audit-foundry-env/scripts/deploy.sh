#!/usr/bin/env bash
# =============================================================================
# deploy.sh — Automated, repeatable deployment of the Invoice Audit Agent demo
# (Microsoft Foundry · Capítulo 2 — Build, Observe & Tune)
#
# Usage:
#   cp config.env.example config.env   # edit values
#   ./scripts/deploy.sh config.env
#
# Safe to re-run: every step checks for an existing resource before creating
# it, and resource names are deterministic (no random suffixes), so running
# this twice against the same config.env converges to the same environment
# instead of creating duplicates.
# =============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

CONFIG_FILE="${1:-$REPO_ROOT/config.env}"
if [ ! -f "$CONFIG_FILE" ]; then
  fail "Config file not found: $CONFIG_FILE"
  echo "Copy config.env.example to config.env (or pass a path) and edit the values first." >&2
  exit 1
fi
# shellcheck disable=SC1090
source "$CONFIG_FILE"

require_cmd az
require_cmd curl
require_cmd python3

step "0/10 — Azure login & subscription context"
az account show >/dev/null 2>&1 || az login --tenant "$AZURE_TENANT_ID"
az account set --subscription "$AZURE_SUBSCRIPTION_ID"
ok "Using subscription $AZURE_SUBSCRIPTION_ID (tenant $AZURE_TENANT_ID)"

SUB_ID="$AZURE_SUBSCRIPTION_ID"

step "0b/10 — Resource provider registration"
for rp in Microsoft.CognitiveServices Microsoft.Storage Microsoft.Search Microsoft.Insights Microsoft.MachineLearningServices; do
  state=$(az provider show -n "$rp" --query registrationState -o tsv 2>/dev/null || echo "NotRegistered")
  if [ "$state" != "Registered" ]; then
    log "Registering resource provider $rp (state: $state)..."
    az provider register -n "$rp" >/dev/null
  fi
done
retry 300 15 "All resource providers registered" -- bash -c '
  for rp in Microsoft.CognitiveServices Microsoft.Storage Microsoft.Search Microsoft.Insights Microsoft.MachineLearningServices; do
    state=$(az provider show -n "$rp" --query registrationState -o tsv)
    [ "$state" = "Registered" ] || exit 1
  done
'

step "1/10 — Resource group"
az group show -n "$RESOURCE_GROUP" >/dev/null 2>&1 || \
  az group create -n "$RESOURCE_GROUP" -l "$LOCATION" >/dev/null
ok "Resource group: $RESOURCE_GROUP"

step "2/10 — Foundry account (Microsoft.CognitiveServices, kind=AIServices)"
# If this name was deleted recently (e.g. a prior teardown.sh run), Azure soft-deletes
# Cognitive Services accounts for a retention period. Purge it so re-deploys don't fail.
if az cognitiveservices account list-deleted --query "[?name=='$FOUNDRY_ACCOUNT_NAME']" -o tsv 2>/dev/null | grep -q "$FOUNDRY_ACCOUNT_NAME"; then
  warn "Purging soft-deleted Foundry account '$FOUNDRY_ACCOUNT_NAME' from a previous teardown..."
  az cognitiveservices account purge -n "$FOUNDRY_ACCOUNT_NAME" -g "$RESOURCE_GROUP" -l "$LOCATION" >/dev/null 2>&1 || true
  sleep 10
fi
if ! az cognitiveservices account show -n "$FOUNDRY_ACCOUNT_NAME" -g "$RESOURCE_GROUP" >/dev/null 2>&1; then
  az cognitiveservices account create \
    -n "$FOUNDRY_ACCOUNT_NAME" -g "$RESOURCE_GROUP" -l "$LOCATION" \
    --kind AIServices --sku S0 --custom-domain "$FOUNDRY_ACCOUNT_NAME" \
    --assign-identity >/dev/null
  ok "Created Foundry account: $FOUNDRY_ACCOUNT_NAME"
else
  ok "Foundry account already exists: $FOUNDRY_ACCOUNT_NAME"
fi
FOUNDRY_ACCOUNT_ID=$(az cognitiveservices account show -n "$FOUNDRY_ACCOUNT_NAME" -g "$RESOURCE_GROUP" --query id -o tsv)
FOUNDRY_ENDPOINT=$(az cognitiveservices account show -n "$FOUNDRY_ACCOUNT_NAME" -g "$RESOURCE_GROUP" --query properties.endpoint -o tsv)

step "2b/10 — Foundry project (child resource)"
TOKEN=$(arm_token)
PROJECT_URL="https://management.azure.com${FOUNDRY_ACCOUNT_ID}/projects/${PROJECT_NAME}?api-version=2025-06-01"
HTTP_CODE=$(curl -s -o /tmp/project_resp.json -w "%{http_code}" -X PUT "$PROJECT_URL" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d "{\"location\": \"$LOCATION\", \"identity\": {\"type\": \"SystemAssigned\"}, \"properties\": {\"displayName\": \"$PROJECT_NAME\"}}")
if [[ "$HTTP_CODE" != "200" && "$HTTP_CODE" != "201" ]]; then
  fail "Project creation failed (HTTP $HTTP_CODE)"; cat /tmp/project_resp.json >&2; exit 1
fi
ok "Foundry project: $PROJECT_NAME (HTTP $HTTP_CODE)"
PROJECT_RESOURCE_ID="${FOUNDRY_ACCOUNT_ID}/projects/${PROJECT_NAME}"
PROJECT_PRINCIPAL_ID=$(python3 -c "import json;print(json.load(open('/tmp/project_resp.json'))['identity']['principalId'])")
FOUNDRY_PRINCIPAL_ID=$(az cognitiveservices account show -n "$FOUNDRY_ACCOUNT_NAME" -g "$RESOURCE_GROUP" --query identity.principalId -o tsv)
PROJECT_ENDPOINT="https://${FOUNDRY_ACCOUNT_NAME}.services.ai.azure.com/api/projects/${PROJECT_NAME}"
ok "Project endpoint: $PROJECT_ENDPOINT"

step "3/10 — Model deployments (agent model, KB model, embedding model)"
deploy_model() {
  local deployment_name="$1" model_name="$2" model_version="$3"
  if az cognitiveservices account deployment show -n "$FOUNDRY_ACCOUNT_NAME" -g "$RESOURCE_GROUP" \
      --deployment-name "$deployment_name" >/dev/null 2>&1; then
    ok "Deployment '$deployment_name' already exists"
    return 0
  fi
  az cognitiveservices account deployment create \
    -n "$FOUNDRY_ACCOUNT_NAME" -g "$RESOURCE_GROUP" \
    --deployment-name "$deployment_name" \
    --model-name "$model_name" --model-version "$model_version" \
    --model-format OpenAI --sku-name GlobalStandard --sku-capacity "$MODEL_SKU_CAPACITY" >/dev/null
  ok "Deployed model '$deployment_name' ($model_name $model_version)"
}
deploy_model "$AGENT_MODEL_NAME" "$AGENT_MODEL_NAME" "$AGENT_MODEL_VERSION"
deploy_model "$KB_MODEL_NAME" "$KB_MODEL_NAME" "$KB_MODEL_VERSION"
deploy_model "$EMBEDDING_MODEL_NAME" "$EMBEDDING_MODEL_NAME" "$EMBEDDING_MODEL_VERSION"

step "4/10 — Knowledge documents (uploaded directly to Search, no storage account needed)"
ok "Knowledge documents will be uploaded directly to the File knowledge source after it is created (step 7)."

step "5/10 — Azure AI Search (serverless)"
if ! az search service show -n "$SEARCH_SERVICE_NAME" -g "$RESOURCE_GROUP" >/dev/null 2>&1; then
  az rest --method put \
    --uri "https://management.azure.com/subscriptions/${SUB_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Search/searchServices/${SEARCH_SERVICE_NAME}?api-version=2026-09-01-Preview" \
    --body "{\"location\": \"$SEARCH_LOCATION\", \"sku\": {\"name\": \"serverless\"}, \"identity\": {\"type\": \"SystemAssigned\"}, \"properties\": {\"disableLocalAuth\": true, \"semanticSearch\": \"standard\"}}" >/dev/null
  # semanticSearch MUST be "standard" (not the default "free") — Foundry IQ knowledge
  # sources fail to create with a generic 500 error otherwise. Confirmed by diffing
  # a working manually-created Search service against a freshly scripted one.
  ok "Created Azure AI Search service: $SEARCH_SERVICE_NAME"
else
  ok "Azure AI Search service already exists: $SEARCH_SERVICE_NAME"
  # Ensure system-assigned identity is present even if the service pre-existed without one.
  _existing_identity=$(az search service show -n "$SEARCH_SERVICE_NAME" -g "$RESOURCE_GROUP" --query "identity.type" -o tsv 2>/dev/null || echo "")
  if [ "$_existing_identity" != "SystemAssigned" ]; then
    az rest --method patch \
      --uri "https://management.azure.com/subscriptions/${SUB_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Search/searchServices/${SEARCH_SERVICE_NAME}?api-version=2026-09-01-Preview" \
      --body '{"identity": {"type": "SystemAssigned"}}' >/dev/null
  fi
  # Ensure semanticSearch is "standard" even if the service pre-existed with "free"
  # (required for Foundry IQ knowledge sources — see note above).
  _existing_semantic=$(az search service show -n "$SEARCH_SERVICE_NAME" -g "$RESOURCE_GROUP" --query "semanticSearch" -o tsv 2>/dev/null || echo "")
  if [ "$_existing_semantic" != "standard" ]; then
    az rest --method patch \
      --uri "https://management.azure.com/subscriptions/${SUB_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Search/searchServices/${SEARCH_SERVICE_NAME}?api-version=2026-09-01-Preview" \
      --body '{"properties": {"semanticSearch": "standard"}}' >/dev/null
    ok "Upgraded semanticSearch to 'standard' on existing service"
  fi
fi
SEARCH_ID="/subscriptions/${SUB_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Search/searchServices/${SEARCH_SERVICE_NAME}"
SEARCH_PRINCIPAL_ID=$(az rest --method get --uri "https://management.azure.com${SEARCH_ID}?api-version=2026-09-01-Preview" --query identity.principalId -o tsv)
SEARCH_ENDPOINT="https://${SEARCH_SERVICE_NAME}.search.windows.net"

step "6/10 — RBAC role assignments (allow 1–10 min to propagate)"
assign_role "$SEARCH_PRINCIPAL_ID" "Cognitive Services User" "$FOUNDRY_ACCOUNT_ID"
assign_role "$PROJECT_PRINCIPAL_ID" "Search Index Data Reader" "$SEARCH_ID"
assign_role "$PROJECT_PRINCIPAL_ID" "Search Service Contributor" "$SEARCH_ID"
# Required for Capítulo 2's "Recurring evaluations" and "Scheduled red teaming" demo
# add-ons (Monitor tab). Without this, the "Create recurring evaluation" wizard fails
# with: "The project managed identity could not access the project... lacks the
# required data action Microsoft.CognitiveServices/accounts/AIServices/assets/read".
assign_role "$PROJECT_PRINCIPAL_ID" "Foundry User" "$FOUNDRY_ACCOUNT_ID"

step "7/10 — Knowledge source (File, direct upload) + knowledge base (Foundry IQ)"
KB_MODEL_DEPLOY_URI="${FOUNDRY_ENDPOINT%/}"
# Defensive cleanup: Azure AI Search rejects updating an existing Knowledge Source's
# embedding endpoint ("The embedding endpoint cannot be changed") once it has been set.
# If this script is ever re-run against the same Search service after the Foundry
# account was recreated under a different name (e.g. after a purge, or because
# FOUNDRY_ACCOUNT_NAME changed in config.env), the leftover Knowledge Source/Base from
# the previous account would permanently block every future PUT with that error. Always
# delete any existing Knowledge Base and Knowledge Source with these names first
# (ignore 404) so creation is truly idempotent regardless of which Foundry account
# previously owned them.
curl -s -X DELETE "${SEARCH_ENDPOINT}/knowledgebases('${KNOWLEDGE_BASE_NAME}')?api-version=2026-08-01-preview" \
  -H "Authorization: Bearer $(search_token)" >/dev/null 2>&1 || true
curl -s -X DELETE "${SEARCH_ENDPOINT}/knowledgesources('${KNOWLEDGE_SOURCE_NAME}')?api-version=2026-08-01-preview" \
  -H "Authorization: Bearer $(search_token)" >/dev/null 2>&1 || true

knowledge_source_body=$(cat <<JSON
{
  "name": "$KNOWLEDGE_SOURCE_NAME",
  "kind": "file",
  "description": "MSA-2025-0417 contract, overtime pre-approval log, and ServicePro invoices for Meridian Manufacturing.",
  "fileParameters": {
    "ingestionParameters": {
      "embeddingModel": {
        "kind": "azureOpenAI",
        "azureOpenAIParameters": {
          "resourceUri": "$KB_MODEL_DEPLOY_URI",
          "deploymentId": "$EMBEDDING_MODEL_NAME",
          "modelName": "$EMBEDDING_MODEL_NAME"
        }
      },
      "contentExtractionMode": "minimal"
    }
  }
}
JSON
)
retry "$RBAC_WAIT_TIMEOUT_SECONDS" "$RBAC_POLL_INTERVAL_SECONDS" "Knowledge source '$KNOWLEDGE_SOURCE_NAME' created" -- \
  curl -sf -X PUT "${SEARCH_ENDPOINT}/knowledgesources('${KNOWLEDGE_SOURCE_NAME}')?api-version=2026-08-01-preview" \
    -H "Authorization: Bearer $(search_token)" -H "Content-Type: application/json" -H "Prefer: return=representation" \
    -d "$knowledge_source_body"

step "7b/10 — Uploading knowledge documents to the File knowledge source"
for f in "$REPO_ROOT"/knowledge-docs/*.txt; do
  fname="$(basename "$f")"
  retry 60 10 "Uploaded $fname" -- \
    curl -sf -X POST "${SEARCH_ENDPOINT}/knowledgesources('${KNOWLEDGE_SOURCE_NAME}')/files?api-version=2026-08-01-preview" \
      -H "Authorization: Bearer $(search_token)" \
      -F "metadata={\"fileName\": \"$fname\"};type=application/json" \
      -F "content=@${f};filename=${fname};type=text/plain"
done

knowledge_base_body=$(cat <<JSON
{
  "name": "$KNOWLEDGE_BASE_NAME",
  "description": "Contract (MSA-2025-0417), overtime approval log, and vendor invoices for ServicePro Staffing Solutions audits.",
  "knowledgeSources": [ { "name": "$KNOWLEDGE_SOURCE_NAME" } ],
  "models": [
    {
      "kind": "azureOpenAI",
      "azureOpenAIParameters": {
        "resourceUri": "$KB_MODEL_DEPLOY_URI",
        "deploymentId": "$KB_MODEL_NAME",
        "modelName": "$KB_MODEL_NAME"
      }
    }
  ],
  "retrievalReasoningEffort": { "kind": "minimal" },
  "outputMode": "extractiveData",
  "retrievalInstructions": "Prioritize the contract and approval log when the question is about billing compliance or overtime approvals."
}
JSON
)
retry "$RBAC_WAIT_TIMEOUT_SECONDS" "$RBAC_POLL_INTERVAL_SECONDS" "Knowledge base '$KNOWLEDGE_BASE_NAME' created" -- \
  curl -sf -X PUT "${SEARCH_ENDPOINT}/knowledgebases('${KNOWLEDGE_BASE_NAME}')?api-version=2026-08-01-preview" \
    -H "Authorization: Bearer $(search_token)" -H "Content-Type: application/json" -H "Prefer: return=representation" \
    -d "$knowledge_base_body"

step "8/10 — Project connection to the knowledge base (MCP)"
MCP_ENDPOINT="${SEARCH_ENDPOINT}/knowledgebases/${KNOWLEDGE_BASE_NAME}/mcp?api-version=2026-08-01-preview"
connection_body=$(cat <<JSON
{
  "name": "$PROJECT_CONNECTION_NAME",
  "type": "Microsoft.MachineLearningServices/workspaces/connections",
  "properties": {
    "authType": "ProjectManagedIdentity",
    "category": "RemoteTool",
    "target": "$MCP_ENDPOINT",
    "isSharedToAll": true,
    "audience": "https://search.azure.com",
    "metadata": { "knowledgeBaseName": "$KNOWLEDGE_BASE_NAME", "type": "knowledgeBase_MCP" }
  }
}
JSON
)
retry "$RBAC_WAIT_TIMEOUT_SECONDS" "$RBAC_POLL_INTERVAL_SECONDS" "Project connection '$PROJECT_CONNECTION_NAME' created" -- \
  curl -sf -X PUT "https://management.azure.com${PROJECT_RESOURCE_ID}/connections/${PROJECT_CONNECTION_NAME}?api-version=2025-10-01-preview" \
    -H "Authorization: Bearer $(arm_token)" -H "Content-Type: application/json" \
    -d "$connection_body"

step "9/10 — Application Insights (Traces/Monitor)"
if ! az monitor app-insights component show --app "$APP_INSIGHTS_NAME" -g "$RESOURCE_GROUP" >/dev/null 2>&1; then
  az monitor app-insights component create --app "$APP_INSIGHTS_NAME" -g "$RESOURCE_GROUP" -l "$LOCATION" \
    --application-type web >/dev/null
  ok "Created Application Insights: $APP_INSIGHTS_NAME"
else
  ok "Application Insights already exists: $APP_INSIGHTS_NAME"
fi
APPI_ID=$(az monitor app-insights component show --app "$APP_INSIGHTS_NAME" -g "$RESOURCE_GROUP" --query id -o tsv)
APPI_CONNECTION_STRING=$(az monitor app-insights component show --app "$APP_INSIGHTS_NAME" -g "$RESOURCE_GROUP" --query connectionString -o tsv)
assign_role "$PROJECT_PRINCIPAL_ID" "Monitoring Reader" "$APPI_ID"

appi_connection_body=$(cat <<JSON
{
  "name": "${APP_INSIGHTS_NAME}",
  "type": "Microsoft.MachineLearningServices/workspaces/connections",
  "properties": {
    "authType": "ApiKey",
    "category": "AppInsights",
    "target": "$APPI_ID",
    "isSharedToAll": true,
    "credentials": { "key": "$APPI_CONNECTION_STRING" },
    "metadata": { "ApiType": "Azure", "ResourceId": "$APPI_ID" }
  }
}
JSON
)
if curl -sf -X PUT "https://management.azure.com${PROJECT_RESOURCE_ID}/connections/${APP_INSIGHTS_NAME}?api-version=2025-10-01-preview" \
    -H "Authorization: Bearer $(arm_token)" -H "Content-Type: application/json" -d "$appi_connection_body" >/tmp/appi_conn.json 2>&1; then
  ok "Linked Application Insights to the project"
else
  warn "Automatic App Insights linking didn't confirm success — open the agent's Traces tab in the portal once and click 'Connect' if Traces/Monitor appear empty (picks the resource created above: $APP_INSIGHTS_NAME)."
fi

step "10/10 — Create the agent and connect the knowledge base"
# Defensive cleanup: the Foundry agent registry has been observed to retain a stale
# agent definition under the same name even after the resource group/account that
# created it was fully deleted and purged (it survives independently of the ARM
# resource lifecycle, keyed by project+agent name). If a leftover agent exists with
# an outdated config (e.g. pointing at a previous deployment's Search service/model
# names), every creation attempt below would otherwise fail forever with HTTP 409
# "Agent already exists" while curl -sf reports it as "not ready yet". Always delete
# any existing agent with this name first (ignore 404) so creation is truly idempotent.
curl -s -X DELETE "${PROJECT_ENDPOINT}/agents/${AGENT_NAME}?api-version=v1" \
  -H "Authorization: Bearer $(ai_token)" >/dev/null 2>&1 || true

agent_body=$(cat <<JSON
{
  "name": "$AGENT_NAME",
  "definition": {
    "model": "$AGENT_MODEL_NAME",
    "kind": "prompt",
    "instructions": "You are the Invoice Audit Agent for Meridian Manufacturing's Procurement team. Your job is to audit vendor invoices from ServicePro Staffing Solutions against the Master Services Agreement (MSA-2025-0417) and the overtime pre-approval log.\n\nFor every invoice you review:\n1. Check every overtime (OT) line item against the approved overtime pre-approval log. Every OT line must reference a valid approval number that exists in the approval log for that site and month.\n2. Flag any OT hours billed with no matching approval reference, or whose approval reference doesn't match the worker ID, as non-billable per MSA Section 3.2.\n3. Calculate the dollar amount of any non-billable OT hours and clearly state it.\n4. Cite the specific contract clause and the specific line in the approval log that supports your finding — never state a finding without grounding it in retrievable contract or policy evidence.\n5. Recommend a clear disposition: Approve, Escalate (credit required), or Needs More Info.\n6. Keep responses structured and professional, suitable to share with a business stakeholder.",
    "tools": [
      {
        "type": "mcp",
        "server_label": "$PROJECT_CONNECTION_NAME",
        "server_url": "$MCP_ENDPOINT",
        "require_approval": "never",
        "project_connection_id": "$PROJECT_CONNECTION_NAME"
      }
    ]
  }
}
JSON
)
retry "$RBAC_WAIT_TIMEOUT_SECONDS" "$RBAC_POLL_INTERVAL_SECONDS" "Agent '$AGENT_NAME' created with knowledge base connected" -- \
  curl -sf -X POST "${PROJECT_ENDPOINT}/agents?api-version=v1" \
    -H "Authorization: Bearer $(ai_token)" -H "Content-Type: application/json" \
    -d "$agent_body"

if [ "${SEED_SAMPLE_TRAFFIC:-true}" = "true" ]; then
  step "Seeding sample traffic (for Traces/Monitor)"
  send_sample() {
    local question="$1"
    curl -s -X POST "${PROJECT_ENDPOINT}/openai/v1/responses" \
    -H "Authorization: Bearer $(ai_token)" -H "Content-Type: application/json" \
      -d "{\"agent_reference\": {\"type\": \"agent_reference\", \"name\": \"$AGENT_NAME\"}, \"input\": \"$question\"}" \
      -o /tmp/sample_resp.json -w "%{http_code}"
  }
  Q1="Please audit invoice INV-2026-08602 from ServicePro Staffing Solutions (Columbus, OH site, August 2026) against the MSA and the overtime pre-approval log. Flag any non-billable overtime and tell me the dollar amount at risk."
  Q2="Now audit invoice INV-2026-08487 from ServicePro Staffing Solutions (Queretaro, MX site, July 2026) the same way. Is it compliant?"
  Q3="What is the SLA fill-rate requirement for ServicePro and what happens if they miss it? Cite the MSA section."

  # The agent's MCP tool call to the knowledge base goes through its own data-plane
  # RBAC check on the Search service. This check has been observed to lag well behind
  # both the role-assignment write (instant) AND even the agent-creation success check
  # above (which only verifies the agent object was created, not that retrieval works
  # yet) -- by several extra minutes on a freshly created/purged environment. Retry the
  # FIRST sample question until it actually returns HTTP 200 (not just "curl succeeded");
  # once real retrieval has worked once, propagation is complete and the rest go through
  # immediately.
  first=true
  for q in "$Q1" "$Q2" "$Q3"; do
    if [ "$first" = "true" ]; then
      waited=0
      while true; do
        code=$(send_sample "$q")
        [ "$code" = "200" ] && break
        if [ "$waited" -ge "$RBAC_WAIT_TIMEOUT_SECONDS" ]; then
          break
        fi
        warn "Knowledge base retrieval not ready yet (HTTP $code), retrying in ${RBAC_POLL_INTERVAL_SECONDS}s (waited ${waited}s/${RBAC_WAIT_TIMEOUT_SECONDS}s)"
        sleep "$RBAC_POLL_INTERVAL_SECONDS"
        waited=$((waited + RBAC_POLL_INTERVAL_SECONDS))
      done
      first=false
    else
      code=$(send_sample "$q")
    fi
    if [ "$code" = "200" ]; then ok "Sample question answered (HTTP $code)"; else warn "Sample question returned HTTP $code -- send it manually from the Playground if Traces look empty."; cat /tmp/sample_resp.json >&2 || true; fi
    sleep 3
  done
fi

echo
echo "============================================================================="
ok "Deployment complete."
echo "Project endpoint:   $PROJECT_ENDPOINT"
echo "Portal URL:         https://ai.azure.com (select project '$PROJECT_NAME' under account '$FOUNDRY_ACCOUNT_NAME')"
echo
echo "Remaining manual steps (documented in the guide):"
echo "  - (~5 min) Create the custom Evaluator ('Contract-Policy-Evidence Compliance') and"
echo "    run an evaluation against the seeded traces. This relies on the portal's rubric"
echo "    auto-generation feature, which does not yet have a stable public REST API."
echo "  - (~5 min, optional) Pre-configure the Monitor tab's 'Recurring evaluations' (Build >"
echo "    Evaluations > Create > Frequency = Recurring) and, if desired, a one-time 'Red"
echo "    team' scan (Build > Evaluations > Red team > Create). Both are portal-only wizards"
echo "    with no stable public REST API yet. Note: the 'Create red teaming run' wizard has"
echo "    NO recurring/scheduled option -- it only submits a one-time run, even though the"
echo "    Monitor tab separately shows a 'Scheduled red teaming runs' toggle (still Disabled"
echo "    / not wired to this wizard as of this writing)."
echo "============================================================================="
