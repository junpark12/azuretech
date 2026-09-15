#!/usr/bin/env bash
# Source-derived command reference. Running this file provisions billable resources.
# Review quota, region, permissions, names and cost before an explicitly approved run.
set -euo pipefail
: "${AZURE_SUBSCRIPTION_ID:?Set AZURE_SUBSCRIPTION_ID}"
: "${AZURE_RESOURCE_GROUP:?Set AZURE_RESOURCE_GROUP}"
: "${FOUNDRY_ACCOUNT_NAME:?Set FOUNDRY_ACCOUNT_NAME}"
: "${FOUNDRY_DEPLOYMENT_NAME:?Set FOUNDRY_DEPLOYMENT_NAME}"
: "${AI_GATEWAY_NAME:?Set AI_GATEWAY_NAME after portal creation}"
: "${AI_GATEWAY_PRINCIPAL_ID:?Set AI_GATEWAY_PRINCIPAL_ID}"

az cognitiveservices account create \
  --subscription "$AZURE_SUBSCRIPTION_ID" \
  -n "$FOUNDRY_ACCOUNT_NAME" -g "$AZURE_RESOURCE_GROUP" -l eastus2 \
  --kind AIServices --sku S0 --custom-domain "$FOUNDRY_ACCOUNT_NAME" --yes

az cognitiveservices account deployment create \
  --subscription "$AZURE_SUBSCRIPTION_ID" \
  -g "$AZURE_RESOURCE_GROUP" -n "$FOUNDRY_ACCOUNT_NAME" \
  --deployment-name "$FOUNDRY_DEPLOYMENT_NAME" \
  --model-name gpt-5-mini --model-version 2025-08-07 \
  --model-format OpenAI --sku-name GlobalStandard --sku-capacity 1

# The gateway is created separately in the standalone portal, not by this file.
az resource show \
  --ids "/subscriptions/$AZURE_SUBSCRIPTION_ID/resourceGroups/$AZURE_RESOURCE_GROUP/providers/Microsoft.ApiManagement/service/$AI_GATEWAY_NAME" \
  --query "{sku:sku.name, capacity:sku.capacity, url:properties.gatewayUrl, identity:identity.principalId}" -o json

az role assignment list --subscription "$AZURE_SUBSCRIPTION_ID" \
  --assignee "$AI_GATEWAY_PRINCIPAL_ID" --all \
  --query "[].{role:roleDefinitionName, scope:scope}" -o table

az resource list --subscription "$AZURE_SUBSCRIPTION_ID" -g "$AZURE_RESOURCE_GROUP" \
  --query "[].{n:name,t:type}" -o tsv

az resource list --subscription "$AZURE_SUBSCRIPTION_ID" -g "$AZURE_RESOURCE_GROUP" \
  --query "[?type=='Microsoft.Insights/components'].name" -o tsv

az resource list --subscription "$AZURE_SUBSCRIPTION_ID" \
  --resource-type "microsoft.monitor/accounts" \
  --query "[].{n:name, rg:resourceGroup}" -o table
