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

# CSV output file
CSV_FILE="strongdm_user_audit_$(date +%Y-%m-%d).csv"
echo "Email,Name,Last Activity,Status" > "$CSV_FILE"

# Process and print report
# Initialize counters
active_count=0
inactive_count=0

while IFS=$'\t' read -r email name; do
  last_seen=$(grep -F "$email" "$TMP_ACTIVITY" | cut -f2)
  if [ -n "$last_seen" ]; then
    status="Active"
    ((active_count++))
  else
    last_seen="Never"
    status="Inactive"
    ((inactive_count++))
  fi
  # Print to terminal
  printf "%-40s | %-25s | %-25s | %-10s\n" "$email" "$name" "$last_seen" "$status"
  # Append to CSV
  echo "\"$email\",\"$name\",\"$last_seen\",\"$status\"" >> "$CSV_FILE"
done < "$TMP_USERS"

# Append summary to CSV
echo ",,," >> "$CSV_FILE"
echo "Total Active,$active_count" >> "$CSV_FILE"
echo "Total Inactive,$inactive_count" >> "$CSV_FILE"

# Print summary to terminal
echo -e "\n📊 Summary:"
echo "✅ Active users:   $active_count"
echo "❌ Inactive users: $inactive_count"
echo -e "\n📄 CSV report written to: $CSV_FILE"

# Cleanup
rm -f "$TMP_USERS" "$TMP_ACTIVITY"