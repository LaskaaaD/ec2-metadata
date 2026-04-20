#!/usr/bin/env bash
#
# ec2-metadata.sh
# Collects EC2 instance metadata via IMDSv2, writes a report file,
# and uploads it to the specified S3 location.
#
# Usage:
#   ./ec2-metadata.sh [--bucket s3://bucket/prefix] [--output /path/to/file.txt]
#
# Requirements:
#   - Runs on an EC2 instance with IMDSv2 available
#   - AWS CLI installed and credentials resolvable (IAM instance role preferred)

set -euo pipefail
umask 077

# ————————————————————————————————————————————————————————————————
# Cleanup
# ————————————————————————————————————————————————————————————————
TMPFILE=""
cleanup() {
    [[ -n "$TMPFILE" && -f "$TMPFILE" ]] && rm -f "$TMPFILE"
}
trap cleanup EXIT

# ————————————————————————————————————————————————————————————————
# Defaults
# ————————————————————————————————————————————————————————————————
S3_URI_DEFAULT="s3://applicant-task/instance-99"
OUTPUT_DIR_DEFAULT="/tmp"
S3_URI="${S3_URI:-$S3_URI_DEFAULT}"
OUTPUT_FILE=""

# ————————————————————————————————————————————————————————————————
# Arg parsing
# ————————————————————————————————————————————————————————————————
while [[ $# -gt 0 ]]; do
    case "$1" in
        --bucket) S3_URI="$2"; shift 2 ;;
        --output) OUTPUT_FILE="$2"; shift 2 ;;
        -h|--help)
            grep -E '^#( |$)' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) echo "Unknown arg: $1" >&2; exit 2 ;;
    esac
done

# ————————————————————————————————————————————————————————————————
# Helpers
# ————————————————————————————————————————————————————————————————
log() { printf '[%s] %s\n' "$(date -u +%FT%TZ)" "$*" >&2; }
die() { log "ERROR: $*"; exit 1; }

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "missing dependency: $1"
}

require_cmd curl
require_cmd aws

IMDS_HOST="http://169.254.169.254"
IMDS_BASE="$IMDS_HOST/latest/meta-data"

get_imds_token() {
    curl -sS --max-time 3 -X PUT "$IMDS_HOST/latest/api/token" \
        -H "X-aws-ec2-metadata-token-ttl-seconds: 300"
}

imds() {
    local path="$1" code body
    TMPFILE=$(mktemp)
    code=$(curl -sS --max-time 3 \
        -H "X-aws-ec2-metadata-token: $TOKEN" \
        -o "$TMPFILE" -w '%{http_code}' \
        "$IMDS_BASE/$path") || die "IMDS request failed for $path"
    if [[ "$code" == "200" ]]; then
        cat "$TMPFILE"
    elif [[ "$code" == "404" ]]; then
        echo ""
    else
        die "IMDS returned HTTP $code for $path"
    fi
    rm -f "$TMPFILE"
    TMPFILE=""
}

# ————————————————————————————————————————————————————————————————
# Fetch metadata
# ————————————————————————————————————————————————————————————————
log "fetching IMDSv2 token"
TOKEN=$(get_imds_token) || die "cannot obtain IMDSv2 token (is this an EC2 instance?)"
[[ -n "$TOKEN" ]] || die "empty IMDSv2 token"

log "querying metadata"
INSTANCE_ID=$(imds "instance-id")
PUBLIC_IP=$(imds  "public-ipv4")
PRIVATE_IP=$(imds "local-ipv4")
SECURITY_GROUPS=$(imds "security-groups")

# ————————————————————————————————————————————————————————————————
# OS info
# ————————————————————————————————————————————————————————————————
if [[ -r /etc/os-release ]]; then
    # shellcheck source=/dev/null
    . /etc/os-release
    OS_STRING="${PRETTY_NAME:-${NAME:-unknown} ${VERSION:-}}"
else
    OS_STRING="$(uname -sr)"
fi

# ————————————————————————————————————————————————————————————————
# Users with bash/sh shells
# ————————————————————————————————————————————————————————————————
BASH_SH_USERS=$(awk -F: '
    {
        n = split($7, parts, "/")
        shell = parts[n]
        if (shell == "bash" || shell == "sh") print $1
    }
' /etc/passwd | sort -u | paste -sd ',' -)

# ————————————————————————————————————————————————————————————————
# Write report
# ————————————————————————————————————————————————————————————————
TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)
if [[ -z "$OUTPUT_FILE" ]]; then
    OUTPUT_FILE="${OUTPUT_DIR_DEFAULT}/ec2-metadata-${INSTANCE_ID:-unknown}-${TIMESTAMP}.txt"
fi

log "writing report to $OUTPUT_FILE"
{
    echo "# EC2 Instance Metadata Report"
    echo "# generated: ${TIMESTAMP}"
    echo "# host:      $(hostname -f 2>/dev/null || hostname)"
    echo "# script:    $(basename "$0")"
    echo
    echo "Instance ID:      ${INSTANCE_ID:-<unavailable>}"
    echo "Public IP:        ${PUBLIC_IP:-<none>}"
    echo "Private IP:       ${PRIVATE_IP:-<unavailable>}"
    echo "Security Groups:  ${SECURITY_GROUPS:-<none>}"
    echo "Operating System: ${OS_STRING}"
    echo "Users (bash/sh):  ${BASH_SH_USERS:-<none>}"
} > "$OUTPUT_FILE"
chmod 600 "$OUTPUT_FILE"

log "report written: $OUTPUT_FILE"

# ————————————————————————————————————————————————————————————————
# Upload
# ————————————————————————————————————————————————————————————————
S3_URI_TRIMMED="${S3_URI%/}"
S3_KEY="${S3_URI_TRIMMED}/$(basename "$OUTPUT_FILE")"

log "uploading to $S3_KEY"
aws s3 cp "$OUTPUT_FILE" "$S3_KEY" --only-show-errors

log "done: $S3_KEY"
echo "$S3_KEY"
