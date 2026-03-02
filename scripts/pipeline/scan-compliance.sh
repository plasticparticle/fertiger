#!/usr/bin/env bash
# scripts/pipeline/scan-compliance.sh
#
# Scans the source tree for patterns that may indicate unregistered personal
# data handling, external processors, data stores, and AI processing.
# Used by the Compliance Audit Agent to detect drift from docs/COMPLIANCE.md.
#
# Usage:  scripts/pipeline/scan-compliance.sh [SOURCE_DIR...]
#         SOURCE_DIR — directories to scan (default: auto-detect src/ lib/ app/ pkg/)
#
# Output: labelled sections readable by the agent. Each section ends with a
#         blank line. The agent reads the sections and cross-references against
#         COMPLIANCE.md.
#
# Environment (sourced from .claude/config.sh):
#   PIPELINE_DOCS_DIR — where COMPLIANCE.md lives

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$ROOT_DIR"

source ".claude/config.sh"

# ── Source directory detection ─────────────────────────────────────────────────
if [ $# -gt 0 ]; then
  SOURCE_DIRS=("$@")
else
  SOURCE_DIRS=()
  for d in src lib app pkg; do
    [ -d "$d" ] && SOURCE_DIRS+=("$d")
  done
fi

if [ ${#SOURCE_DIRS[@]} -eq 0 ]; then
  echo "SCAN_ERROR: No source directories found (tried: src/ lib/ app/ pkg/)"
  exit 0
fi

# Shared grep options — exclude noise
GREP_INCLUDE=(
  "--include=*.ts" "--include=*.tsx" "--include=*.js"
  "--include=*.py" "--include=*.go" "--include=*.java"
  "--include=*.cs" "--include=*.rb" "--include=*.rs"
)
GREP_EXCLUDE=(
  "--exclude-dir=node_modules" "--exclude-dir=.git"
  "--exclude-dir=dist" "--exclude-dir=build" "--exclude-dir=.next"
  "--exclude=*.test.*" "--exclude=*.spec.*" "--exclude=*_test.*"
  "--exclude=*.mock.*"
)

echo "=== COMPLIANCE_SCAN ==="
echo "Scanned: ${SOURCE_DIRS[*]}"
echo "Timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
echo ""

# ── 1. Personal Data Field Candidates ─────────────────────────────────────────
# Match field/property/column names that look like PII in non-test source files.
# Lines that are just comments or string literals in UI (labels, placeholders)
# are filtered out with a second pass.
echo "=== PERSONAL_DATA_CANDIDATES ==="
grep -rn \
  "${GREP_INCLUDE[@]}" \
  "${GREP_EXCLUDE[@]}" \
  -iE '\b(email|phone|mobile|address|postcode|zip_code|zipcode|date_of_birth|dateofbirth|dob|birth_date|birthdate|ssn|passport|national_id|nationalid|ip_address|ipaddress|device_id|deviceid|first_name|firstname|last_name|lastname|full_name|fullname|gender|ethnicity|religion|biometric|health_data|medical_record)\b' \
  "${SOURCE_DIRS[@]}" 2>/dev/null \
  | grep -ivE "(placeholder|aria-label|<label|tooltip|description|sample|fixture|example|stub)" \
  | head -60 \
  || echo "(none found)"
echo ""

# ── 2. External API Endpoints ──────────────────────────────────────────────────
# Hardcoded HTTPS URLs pointing outside the project. Filters local and test URLs.
echo "=== EXTERNAL_ENDPOINTS ==="
grep -rhn \
  "${GREP_INCLUDE[@]}" \
  "${GREP_EXCLUDE[@]}" \
  -oE 'https?://[a-zA-Z0-9._-]+\.[a-zA-Z]{2,}(/[a-zA-Z0-9._~:/?#@!$&()*+,;=%-]*)?' \
  "${SOURCE_DIRS[@]}" 2>/dev/null \
  | grep -ivE "(localhost|127\.0\.0\.1|0\.0\.0\.0|::1|example\.(com|org|net)|placeholder|your-domain|test\.|\.test$|schema\.org|w3\.org|json-schema\.org)" \
  | sort -u \
  | head -40 \
  || echo "(none found)"
echo ""

# ── 3. Third-Party SDK Imports ─────────────────────────────────────────────────
# Package imports that indicate data-processor relationships. These may trigger
# cross-border transfer obligations or require DPAs.
echo "=== THIRD_PARTY_SDKS ==="
grep -rn \
  "${GREP_INCLUDE[@]}" \
  "${GREP_EXCLUDE[@]}" \
  -iE "(stripe|twilio|sendgrid|mailchimp|hubspot|salesforce|segment|amplitude|mixpanel|fullstory|hotjar|heap|pendo|datadog|newrelic|sentry|rollbar|bugsnag|intercom|zendesk|braintree|paypal|adyen|plaid|checkr|trulioo|onfido|jumio|vonage|nexmo|messagebird|bandwidth)" \
  "${SOURCE_DIRS[@]}" 2>/dev/null \
  | grep -E "^[^/]*import |^[^#]*import |^[^#]*require\(|^[^#]*from " \
  | grep -v "node_modules" \
  | head -30 \
  || echo "(none found)"
echo ""

# ── 4. Data Stores ─────────────────────────────────────────────────────────────
# Connection strings, ORMs, and storage client initialisations.
echo "=== DATA_STORES ==="
grep -rn \
  "${GREP_INCLUDE[@]}" \
  "${GREP_EXCLUDE[@]}" \
  --include="*.env*" --include="*.yaml" --include="*.yml" \
  -iE "(mongodb://|postgres://|postgresql://|mysql://|redis://|rediss://|amqp://|cosmosdb|cosmos\.azure\.com|dynamodb|s3\.amazonaws\.com|blob\.core\.windows\.net|table\.core\.windows\.net|queue\.core\.windows\.net|bigquery|snowflake\.com|databricks\.com|elasticsearch|cockroachdb|firestore|supabase\.co|planetscale\.com|neon\.tech|turso\.io|cassandra|kafka)" \
  "${SOURCE_DIRS[@]}" 2>/dev/null \
  | head -30 \
  || echo "(none found)"
echo ""

# ── 5. AI / ML Processing ──────────────────────────────────────────────────────
# Patterns that may trigger EU AI Act classification obligations.
echo "=== AI_PROCESSING ==="
grep -rn \
  "${GREP_INCLUDE[@]}" \
  "${GREP_EXCLUDE[@]}" \
  -iE "(openai\.(chat|completion|embed)|anthropic\.(messages|complete)|azure\.ai\.|cognitiveservices\.azure|\.predict\(|\.classify\(|\.infer\(|model\.fit\(|\.score\(|\.embed\(|langchain|llamaindex|huggingface|transformers\.|torch\.|tensorflow\.|keras\.)" \
  "${SOURCE_DIRS[@]}" 2>/dev/null \
  | head -20 \
  || echo "(none found)"
echo ""

# ── 6. Recent Merges to Source ─────────────────────────────────────────────────
# Finds merged PRs that touched source files since the last compliance audit.
# Used to identify changes that may have bypassed the compliance pipeline.
echo "=== RECENT_MERGES ==="
# Extract last audit date from the Audit Log section of COMPLIANCE.md
LAST_AUDIT=$(grep -oE "<!-- last-audit: [0-9]{4}-[0-9]{2}-[0-9]{2}" \
  "$PIPELINE_DOCS_DIR/COMPLIANCE.md" 2>/dev/null \
  | tail -1 | grep -oE "[0-9]{4}-[0-9]{2}-[0-9]{2}" || echo "")

if [ -n "$LAST_AUDIT" ]; then
  echo "Since last audit: $LAST_AUDIT"
  git log \
    --since="$LAST_AUDIT" \
    --merges \
    --format="%h %s" \
    -- "${SOURCE_DIRS[@]}" 2>/dev/null \
    | grep -oE "#[0-9]+" | grep -oE "[0-9]+" | sort -u \
    | sed 's/^/ISSUE: /' \
    || echo "(none)"
else
  echo "No previous audit found — showing all source-touching merges"
  git log \
    --merges \
    --format="%h %s" \
    -- "${SOURCE_DIRS[@]}" 2>/dev/null \
    | head -20 \
    | grep -oE "#[0-9]+" | grep -oE "[0-9]+" | sort -u \
    | sed 's/^/ISSUE: /' \
    || echo "(none)"
fi
echo ""

echo "=== END_SCAN ==="
