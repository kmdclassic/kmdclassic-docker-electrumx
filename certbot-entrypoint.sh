#!/bin/sh
set -e

# Get environment variables
DOMAIN_NAME=${DOMAIN_NAME:-}
CF_API_TOKEN=${CF_API_TOKEN:-}
CF_EMAIL=${CF_EMAIL:-}
PUID=${PUID:-1000}
PGID=${PGID:-1000}
RENEWAL_INTERVAL=${RENEWAL_INTERVAL:-86400}  # Default: 24 hours in seconds

if [ -z "$DOMAIN_NAME" ] || [ -z "$CF_API_TOKEN" ]; then
    echo "Error: DOMAIN_NAME and CF_API_TOKEN must be set"
    exit 1
fi

# Function to copy certificates to /ssl
copy_certificates() {
    local domain=$1
    echo "Copying certificates for ${domain}..."
    mkdir -p /ssl/${domain}
    
    if [ -f /etc/letsencrypt/live/${domain}/fullchain.pem ] && \
       [ -f /etc/letsencrypt/live/${domain}/privkey.pem ]; then
        cp /etc/letsencrypt/live/${domain}/fullchain.pem /ssl/${domain}/fullchain.pem
        cp /etc/letsencrypt/live/${domain}/privkey.pem /ssl/${domain}/privkey.pem
        
        # Set permissions
        chmod 644 /ssl/${domain}/fullchain.pem
        chmod 600 /ssl/${domain}/privkey.pem
        
        # Try to set ownership if running as root
        if [ "$(id -u)" = "0" ]; then
            chown -R ${PUID}:${PGID} /ssl/${domain} 2>/dev/null || true
        fi
        
        echo "Certificates copied to /ssl/${domain}"
        return 0
    else
        echo "Warning: Certificate files not found for ${domain}"
        return 1
    fi
}

# Function to check if certificate needs renewal
check_renewal_needed() {
    local domain=$1
    local cert_file="/etc/letsencrypt/live/${domain}/cert.pem"
    
    if [ ! -f "$cert_file" ]; then
        echo "Certificate not found for ${domain}, needs to be obtained"
        return 0  # Needs action
    fi
    
    # Check certificate expiration (renew if less than 30 days remaining)
    local days_until_expiry=""
    
    # Use openssl as primary method (more reliable)
    if command -v openssl >/dev/null 2>&1; then
        local expiry_date=$(openssl x509 -enddate -noout -in "$cert_file" 2>/dev/null | cut -d= -f2)
        if [ -n "$expiry_date" ]; then
            # Remove timezone suffix (GMT, UTC, etc.) for better compatibility
            local expiry_date_clean=$(echo "$expiry_date" | sed 's/ GMT$//' | sed 's/ UTC$//')
            
            # Try GNU date (Alpine Linux uses GNU date)
            # Format: "Apr 10 21:22:58 2026" -> convert to epoch
            local expiry_epoch=$(date -d "$expiry_date_clean" +%s 2>/dev/null)
            
            if [ -n "$expiry_epoch" ] && [ "$expiry_epoch" != "0" ]; then
                local current_epoch=$(date +%s)
                days_until_expiry=$(( (expiry_epoch - current_epoch) / 86400 ))
            else
                echo "Warning: Could not parse expiry date: $expiry_date"
            fi
        fi
    fi
    
    # Fallback: Try to get expiration from certbot if openssl failed
    if [ -z "$days_until_expiry" ] && command -v certbot >/dev/null 2>&1; then
        # certbot certificates output format: "Expiry Date: 2026-04-10 21:22:58+00:00 (VALID: 89 days)"
        local certbot_output=$(certbot certificates --cert-name ${domain} 2>/dev/null)
        if [ -n "$certbot_output" ]; then
            # Extract days from "VALID: XX days" pattern (make sure it's not a year)
            local valid_days=$(echo "$certbot_output" | grep -iE "valid.*days" | grep -oE "[0-9]+" | head -1 || echo "")
            # Only use if it's a reasonable number (less than 400 days)
            if [ -n "$valid_days" ] && [ "$valid_days" -lt 400 ]; then
                days_until_expiry="$valid_days"
            fi
        fi
    fi
    
    # Validate days_until_expiry is a reasonable number (not a year like 2026)
    # Certificates typically expire within 90 days (Let's Encrypt) or up to 1 year
    # If value is > 400, it's likely a year, not days
    if [ -n "$days_until_expiry" ] && [ "$days_until_expiry" -gt 400 ]; then
        echo "Warning: Invalid days_until_expiry value ($days_until_expiry), likely parsed incorrectly"
        days_until_expiry=""  # Reset to force recalculation
    fi
    
    # Default to renewal if we can't determine expiration
    if [ -z "$days_until_expiry" ] || [ "$days_until_expiry" = "0" ]; then
        echo "Could not determine certificate expiration for ${domain}, will attempt renewal"
        return 0  # Needs renewal to be safe
    fi
    
    # Check if renewal is needed (less than 30 days)
    if [ "$days_until_expiry" -lt 30 ]; then
        echo "Certificate for ${domain} expires in ${days_until_expiry} days, renewal needed"
        return 0  # Needs renewal
    else
        echo "Certificate for ${domain} is valid for ${days_until_expiry} more days"
        return 1  # No action needed
    fi
}

# Function to obtain or renew certificate
obtain_or_renew_certificate() {
    local domain=$1
    local action=$2  # "obtain" or "renew"
    
    # Create CloudFlare credentials file
    mkdir -p /etc/letsencrypt
    cat > /etc/letsencrypt/cloudflare.ini <<EOF
dns_cloudflare_api_token = ${CF_API_TOKEN}
EOF
    chmod 600 /etc/letsencrypt/cloudflare.ini
    
    if [ "$action" = "obtain" ]; then
        echo "Obtaining new certificate for ${domain}..."
        certbot certonly \
            --dns-cloudflare \
            --dns-cloudflare-credentials /etc/letsencrypt/cloudflare.ini \
            --dns-cloudflare-propagation-seconds 60 \
            --non-interactive \
            --agree-tos \
            --email "${CF_EMAIL:-admin@${domain}}" \
            -d "${domain}"
    else
        echo "Renewing certificate for ${domain}..."
        certbot renew \
            --cert-name ${domain} \
            --dns-cloudflare \
            --dns-cloudflare-credentials /etc/letsencrypt/cloudflare.ini \
            --dns-cloudflare-propagation-seconds 60 \
            --non-interactive \
            --force-renewal
    fi
}

# Main loop
main_loop() {
    while true; do
        echo "=== $(date): Checking certificates for ${DOMAIN_NAME} ==="
        
        # Check if certificate exists
        if [ ! -d "/etc/letsencrypt/live/${DOMAIN_NAME}" ]; then
            echo "Certificate directory not found, obtaining new certificate..."
            if obtain_or_renew_certificate "${DOMAIN_NAME}" "obtain"; then
                copy_certificates "${DOMAIN_NAME}" || echo "Warning: Failed to copy certificates"
            else
                echo "Failed to obtain certificate, will retry on next check"
            fi
        elif check_renewal_needed "${DOMAIN_NAME}"; then
            echo "Certificate needs renewal..."
            if obtain_or_renew_certificate "${DOMAIN_NAME}" "renew"; then
                copy_certificates "${DOMAIN_NAME}" || echo "Warning: Failed to copy certificates"
            else
                echo "Failed to renew certificate, trying to obtain new one..."
                if obtain_or_renew_certificate "${DOMAIN_NAME}" "obtain"; then
                    copy_certificates "${DOMAIN_NAME}" || echo "Warning: Failed to copy certificates"
                else
                    echo "Failed to obtain certificate, will retry on next check"
                fi
            fi
        else
            # Certificate is valid, just ensure it's copied to /ssl
            copy_certificates "${DOMAIN_NAME}" || echo "Warning: Failed to copy certificates"
        fi
        
        echo "Next check in ${RENEWAL_INTERVAL} seconds ($(($RENEWAL_INTERVAL / 3600)) hours)"
        sleep ${RENEWAL_INTERVAL} || break
    done
}

# Run main loop
main_loop

