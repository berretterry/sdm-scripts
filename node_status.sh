#!/bin/bash

echo "📡 Checking StrongDM Node Health..."

# Ensure the user is logged in
if ! sdm ready > /dev/null 2>&1; then
  echo "❌ Not logged in. Please run 'sdm login' first."
  exit 1
fi

# Fetch all nodes (gateways, relays, etc.)
NODES_JSON=$(sdm admin nodes list --json)

if [ -z "$NODES_JSON" ]; then
  echo "❌ Failed to retrieve node data."
  exit 1
fi

# Output table header
printf "\n%-30s | %-15s | %-10s\n" "NAME" "TYPE" "STATUS"
echo "---------------------------------------------------------------------"

# Parse and print all nodes
echo "$NODES_JSON" | jq -r '.[] | [.name, .type, (.status // "Unknown")] | @tsv' \
| while IFS=$'\t' read -r name type status; do
  printf "%-30s | %-15s | %-10s\n" "$name" "$type" "$status"
done