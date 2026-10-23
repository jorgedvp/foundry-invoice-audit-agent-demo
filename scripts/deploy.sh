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

step "1/10 — Resource group"
az group show -n "$RESOURCE_GROUP" >/dev/null 2>&1 || \
  az group create -n "$RESOURCE_GROUP" -l "$LOCATION" >/dev/null
ok "Resource group: $RESOURCE_GROUP"

step "2/10 — Foundry account (Microsoft.CognitiveServices, kind=AIServices)"
if ! az cognitiveservices account show -n "$FOUNDRY_ACCOUNT_NAME" -g "$RESOURCE_GROUP" >/dev/null 2>&1; then
  az cognitiveservices account create \
    -n "$FOUNDRY_ACCOUNT_NAME" -g "$RESOURCE_GROUP" -l "$LOCATION" \
    --kind AIServices --sku S0 --custom-domain "$FOUNDRY_ACCOUNT_NAME" \
    --assign-identity --identity-type SystemAssigned >/dev/null
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

step "4/10 — Storage account + container for knowledge documents"
STORAGE_SUFFIX=$(short_suffix "$RESOURCE_GROUP")
STORAGE_NAME="${STORAGE_ACCOUNT_NAME}${STORAGE_SUFFIX}"
if ! az storage account show -n "$STORAGE_NAME" -g "$RESOURCE_GROUP" >/dev/null 2>&1; then
  az storage account create -n "$STORAGE_NAME" -g "$RESOURCE_GROUP" -l "$LOCATION" \
    --sku Standard_LRS --kind StorageV2 --allow-blob-public-access false >/dev/null
  ok "Created storage account: $STORAGE_NAME"
else
  ok "Storage account already exists: $STORAGE_NAME"
fi
STORAGE_ID=$(az storage account show -n "$STORAGE_NAME" -g "$RESOURCE_GROUP" --query id -o tsv)
CONTAINER_NAME="knowledge-docs"
az storage container create --account-name "$STORAGE_NAME" --name "$CONTAINER_NAME" \
  --auth-mode login >/dev/null 2>&1 || true
for f in "$REPO_ROOT"/knowledge-docs/*.txt; do
  az storage blob upload --account-name "$STORAGE_NAME" --container-name "$CONTAINER_NAME" \
    --name "$(basename "$f")" --file "$f" --auth-mode login --overwrite true >/dev/null
done
ok "Uploaded $(ls "$REPO_ROOT"/knowledge-docs/*.txt | wc -l | tr -d ' ') knowledge documents to blob container '$CONTAINER_NAME'"

step "5/10 — Azure AI Search (serverless) + knowledge resources"
if ! az search service show -n "$SEARCH_SERVICE_NAME" -g "$RESOURCE_GROUP" >/dev/null 2>&1; then
  az rest --method put \
    --uri "https://management.azure.com/subscriptions/${SUB_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Search/searchServices/${SEARCH_SERVICE_NAME}?api-version=2025-05-01" \
    --body "{\"location\": \"$SEARCH_LOCATION\", \"sku\": {\"name\": \"serverless\"}, \"identity\": {\"type\": \"SystemAssigned\"}, \"properties\": {\"disableLocalAuth\": true}}" >/dev/null
  ok "Created Azure AI Search service: $SEARCH_SERVICE_NAME"
else
  ok "Azure AI Search service already exists: $SEARCH_SERVICE_NAME"
  # Ensure system-assigned identity is present even if the service pre-existed without one.
  az rest --method patch \
    --uri "https://management.azure.com/subscriptions/${SUB_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Search/searchServices/${SEARCH_SERVICE_NAME}?api-version=2025-05-01" \
    --body '{"identity": {"type": "SystemAssigned"}}' >/dev/null
fi
SEARCH_ID="/subscriptions/${SUB_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Search/searchServices/${SEARCH_SERVICE_NAME}"
SEARCH_PRINCIPAL_ID=$(az rest --method get --uri "https://management.azure.com${SEARCH_ID}?api-version=2025-05-01" --query identity.principalId -o tsv)
SEARCH_ENDPOINT="https://${SEARCH_SERVICE_NAME}.search.windows.net"

step "6/10 — RBAC role assignments (allow 1–10 min to propagate)"
assign_role "$SEARCH_PRINCIPAL_ID" "Cognitive Services User" "$FOUNDRY_ACCOUNT_ID"
assign_role "$SEARCH_PRINCIPAL_ID" "Storage Blob Data Reader" "$STORAGE_ID"
assign_role "$PROJECT_PRINCIPAL_ID" "Search Index Data Reader" "$SEARCH_ID"
assign_role "$PROJECT_PRINCIPAL_ID" "Search Service Contributor" "$SEARCH_ID"
assign_role "$FOUNDRY_PRINCIPAL_ID" "Storage Blob Data Reader" "$STORAGE_ID"

step "7/10 — Knowledge source + knowledge base (Foundry IQ)"
KB_MODEL_DEPLOY_URI="${FOUNDRY_ENDPOINT%/}"
knowledge_source_body=$(cat <<JSON
{
  "name": "$KNOWLEDGE_SOURCE_NAME",
  "kind": "azureBlob",
  "description": "MSA-2025-0417 contract, overtime pre-approval log, and ServicePro invoices for Meridian Manufacturing.",
  "azureBlobParameters": {
    "connectionString": "ResourceId=${STORAGE_ID};",
    "containerName": "$CONTAINER_NAME",
    "identity": { "@odata.type": "#Microsoft.Azure.Search.DataNoneIdentity" }
  }
}
JSON
)
retry "$RBAC_WAIT_TIMEOUT_SECONDS" "$RBAC_POLL_INTERVAL_SECONDS" "Knowledge source '$KNOWLEDGE_SOURCE_NAME' created" -- \
  curl -sf -X PUT "${SEARCH_ENDPOINT}/knowledgesources('${KNOWLEDGE_SOURCE_NAME}')?api-version=2026-08-01-preview" \
    -H "Authorization: Bearer $(search_token)" -H "Content-Type: application/json" -H "Prefer: return=representation" \
    -d "$knowledge_source_body"

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
    "audience": "https://search.azure.com/",
    "metadata": { "ApiType": "Azure" }
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
  "name": "${APP_INSIGHTS_NAME}-connection",
  "type": "Microsoft.MachineLearningServices/workspaces/connections",
  "properties": {
    "authType": "ApiKey",
    "category": "AppInsights",
    "target": "$APPI_ID",
    "isSharedToAll": true,
    "credentials": { "key": "$APPI_CONNECTION_STRING" },
    "metadata": { "ResourceId": "$APPI_ID" }
  }
}
JSON
)
if curl -sf -X PUT "https://management.azure.com${PROJECT_RESOURCE_ID}/connections/${APP_INSIGHTS_NAME}-connection?api-version=2025-10-01-preview" \
    -H "Authorization: Bearer $(arm_token)" -H "Content-Type: application/json" -d "$appi_connection_body" >/tmp/appi_conn.json 2>&1; then
  ok "Linked Application Insights to the project"
else
  warn "Automatic App Insights linking didn't confirm success — open the agent's Traces tab in the portal once and click 'Connect' if Traces/Monitor appear empty (picks the resource created above: $APP_INSIGHTS_NAME)."
fi

step "10/10 — Create the agent and connect the knowledge base"
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
        "server_label": "knowledge-base",
        "server_url": "$MCP_ENDPOINT",
        "require_approval": "never",
        "allowed_tools": ["knowledge_base_retrieve"],
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
  ai_tok=$(ai_token)
  send_sample() {
    local question="$1"
    curl -sf -X POST "${PROJECT_ENDPOINT}/openai/v1/responses" \
      -H "Authorization: Bearer $ai_tok" -H "Content-Type: application/json" \
      -d "{\"agent\": {\"type\": \"agent_reference\", \"name\": \"$AGENT_NAME\"}, \"input\": \"$question\"}" \
      -o /tmp/sample_resp.json -w "%{http_code}"
  }
  Q1="Please audit invoice INV-2026-08602 from ServicePro Staffing Solutions (Columbus, OH site, August 2026) against the MSA and the overtime pre-approval log. Flag any non-billable overtime and tell me the dollar amount at risk."
  Q2="Now audit invoice INV-2026-08487 from ServicePro Staffing Solutions (Queretaro, MX site, July 2026) the same way. Is it compliant?"
  Q3="What is the SLA fill-rate requirement for ServicePro and what happens if they miss it? Cite the MSA section."
  for q in "$Q1" "$Q2" "$Q3"; do
    code=$(send_sample "$q" || echo "000")
    if [ "$code" = "200" ]; then ok "Sample question answered (HTTP $code)"; else warn "Sample question returned HTTP $code — send it manually from the Playground if Traces look empty."; fi
    sleep 3
  done
fi

echo
echo "============================================================================="
ok "Deployment complete."
echo "Project endpoint:   $PROJECT_ENDPOINT"
echo "Portal URL:         https://ai.azure.com (select project '$PROJECT_NAME' under account '$FOUNDRY_ACCOUNT_NAME')"
echo
echo "Remaining manual step (~5 min, documented in the guide):"
echo "  - Create the custom Evaluator ('Contract-Policy-Evidence Compliance') and run an"
echo "    evaluation against the seeded traces. This relies on the portal's rubric"
echo "    auto-generation feature, which does not yet have a stable public REST API."
echo "============================================================================="
