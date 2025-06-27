#!/bin/bash

# ------------------------
# SETUP
# ------------------------

# Cross-platform 90-day range (macOS -v, Linux -d)
FROM_DATE=$(date -v -90d +%Y-%m-%d 2>/dev/null || date -d "90 days ago" +%Y-%m-%d)
TO_DATE=$(date +%Y-%m-%d)

# Ensure StrongDM CLI is ready
if ! sdm ready > /dev/null 2>&1; then
  echo "❌ Not logged in to StrongDM."
  exit 1
fi

# ------------------------
# FETCH USERS
# ------------------------

echo "📡 Fetching users..."
USER_JSON=$(sdm admin users list --json)
if [ -z "$USER_JSON" ] || ! echo "$USER_JSON" | jq -e 'type == "array"' >/dev/null 2>&1; then
  echo "❌ Could not fetch valid user JSON."
  exit 1
fi

# ------------------------
# FETCH AUDIT LOGS (as NDJSON)
# ------------------------

echo "📡 Fetching audit activity from $FROM_DATE to $TO_DATE..."
AUDIT_RAW=$(sdm audit activities --from "$FROM_DATE" --to "$TO_DATE" -j 2>/dev/null)

if [ -z "$AUDIT_RAW" ]; then
  echo "⚠️  No audit log data returned. Defaulting all users to Inactive."
  AUDIT_RAW=""
fi

# ------------------------
# PARSE EMAIL ACTIVITY FROM DESCRIPTIONS
# ------------------------

TMP_ACTIVITY=$(mktemp)

# Each line is a standalone JSON object
echo "$AUDIT_RAW" | while IFS= read -r line; do
  email=$(echo "$line" | jq -r 'try .description catch ""' | grep -Eo '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' || true)
  timestamp=$(echo "$line" | jq -r 'try .timestamp catch ""')
  if [[ -n "$email" && -n "$timestamp" ]]; then
    echo -e "${email}\t${timestamp}"
  fi
done | sort -k1,1 -k2,2r | awk '!seen[$1]++' > "$TMP_ACTIVITY"

# ------------------------
# PARSE USERS
# ------------------------

TMP_USERS=$(mktemp)
echo "$USER_JSON" | jq -r '.[] | [.email, (.firstName + " " + .lastName)] | @tsv' > "$TMP_USERS"

# ------------------------
# PRINT REPORT
# ------------------------

echo -e "\n📋 StrongDM User Activity Report (Last 90 Days)\n"
printf "%-40s | %-25s | %-30s | %-10s\n" "EMAIL" "NAME" "LAST ACTIVITY" "STATUS"
echo "------------------------------------------------------------------------------------------------------------------------"

while IFS=$'\t' read -r email name; do
  last_seen=$(grep -Fi "$email" "$TMP_ACTIVITY" | cut -f2)
  if [ -n "$last_seen" ]; then
    status="Active"
  else
    last_seen="Not Within 90 Days"
    status="Inactive"
  fi
  printf "%-40s | %-25s | %-30s | %-10s\n" "$email" "$name" "$last_seen" "$status"
done < "$TMP_USERS"

# ------------------------
# CLEANUP
# ------------------------

rm -f "$TMP_USERS" "$TMP_ACTIVITY"