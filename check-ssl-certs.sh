#!/bin/sh
# Check SSL certificate expiry in a directory (default: ssl next to this script).
# Exit 0 if all valid, 1 if any expired or unreadable.

set -e

WARN_DAYS="${SSL_WARN_DAYS:-30}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SSL_DIR="${1:-${SSL_DIR:-$SCRIPT_DIR/ssl}}"

if [ ! -d "$SSL_DIR" ]; then
    echo "Error: directory not found: $SSL_DIR" >&2
    exit 1
fi

if ! command -v openssl >/dev/null 2>&1; then
    echo "Error: openssl not found" >&2
    exit 1
fi

# Find certificate files: prefer fullchain.pem, else any .pem that openssl accepts
find_certs() {
    certs=""
    for f in $(find "$SSL_DIR" -type f -name 'fullchain.pem' 2>/dev/null); do
        certs="$certs $f"
    done
    if [ -z "$certs" ]; then
        for f in $(find "$SSL_DIR" -type f -name '*.pem' 2>/dev/null); do
            if openssl x509 -in "$f" -noout -enddate >/dev/null 2>&1; then
                certs="$certs $f"
            fi
        done
    fi
    echo "$certs"
}

check_one() {
    local file="$1"
    local enddate_raw expiry_date_clean expiry_epoch current_epoch days status
    enddate_raw=$(openssl x509 -enddate -noout -in "$file" 2>/dev/null | cut -d= -f2)
    if [ -z "$enddate_raw" ]; then
        echo "  Status: ERROR (could not read certificate)"
        echo "DAYS:ERROR"
        return 1
    fi
    expiry_date_clean=$(echo "$enddate_raw" | sed 's/ GMT$//' | sed 's/ UTC$//')
    expiry_epoch=$(date -d "$expiry_date_clean" +%s 2>/dev/null)
    if [ -z "$expiry_epoch" ] || [ "$expiry_epoch" = "0" ]; then
        echo "  Expires: $enddate_raw"
        echo "  Status: ERROR (could not parse date)"
        echo "DAYS:ERROR"
        return 1
    fi
    current_epoch=$(date +%s)
    days=$(( (expiry_epoch - current_epoch) / 86400 ))

    if [ "$days" -le 0 ]; then
        status="EXPIRED"
    elif [ "$days" -le "$WARN_DAYS" ]; then
        status="EXPIRING SOON"
    else
        status="OK"
    fi

    echo "  Expires: $enddate_raw"
    echo "  Days left: $days"
    echo "  Status: $status"
    echo "DAYS:$days"
    return 0
}

echo "Checking certificates in $SSL_DIR"
echo "---"

total=0
expired=0
expiring=0

certs=$(find_certs)
for f in $certs; do
    [ -z "$f" ] && continue
    total=$(( total + 1 ))
    echo "$f"
    output=$(check_one "$f" || true)
    echo "$output" | grep -v "^DAYS:" || true
    result=$(echo "$output" | grep "^DAYS:" | cut -d: -f2)
    case "$result" in
        ERROR|"") expired=$(( expired + 1 )) ;;
        *)
            if [ "$result" -le 0 ]; then
                expired=$(( expired + 1 ))
            elif [ "$result" -le "$WARN_DAYS" ]; then
                expiring=$(( expiring + 1 ))
            fi
            ;;
    esac
    echo "---"
done

echo "Summary: $total checked, $expired expired, $expiring expiring soon"

if [ "$expired" -gt 0 ]; then
    exit 1
fi
exit 0
