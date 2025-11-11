# Usage: ./autokerb.sh 10.10.11.93
cat > autokerb.sh << 'EOF'
#!/usr/bin/env bash
set -euo pipefail
DC_IP="${1:-}"
[ -z "$DC_IP" ] && { echo "Usage: $0 <DC_IP_or_FQDN>"; exit 1; }

# 1) Read defaultNamingContext from RootDSE
DN=$(ldapsearch -x -H "ldap://$DC_IP" -s base '' defaultNamingContext 2>/dev/null \
     | awk -F': ' '/defaultNamingContext/{print $2}' | head -n1)

# 2) Convert DN -> domain and realm
DOMAIN=$(echo "$DN" | tr '[:upper:]' '[:lower:]' | sed 's/DC=//g;s/,/./g')
REALM=$(echo "$DOMAIN" | tr '[:lower:]' '[:upper:]')

# 3) Discover KDC/admin_server via DNS SRV (fallback to DC_IP if missing)
KDCs=$(dig +short _kerberos._tcp."$DOMAIN" SRV | awk '{gsub(/\.$/,"",$4); print $4":"$3}')
ADMNs=$(dig +short _kpasswd._tcp."$DOMAIN" SRV | awk '{gsub(/\.$/,"",$4); print $4":"$3}')
[ -z "$KDCs" ] && KDCs="${DC_IP}:88"
[ -z "$ADMNs" ] && ADMNs="${DC_IP}:464"

# 4) Write krb5.conf.d snippet
sudo mkdir -p /etc/krb5.conf.d
sudo tee /etc/krb5.conf.d/"$DOMAIN".conf >/dev/null <<CONF
[libdefaults]
    default_realm = $REALM
    dns_lookup_realm = false
    dns_lookup_kdc = false
    ticket_lifetime = 24h
    renew_lifetime = 7d
    forwardable = true
    rdns = false

[realms]
    $REALM = {
$(printf '        kdc = %s\n' $(echo "$KDCs" | tr '\n' ' '))
        admin_server = $(echo "$ADMNs" | head -n1)
        default_domain = $DOMAIN
    }

[domain_realm]
    .$DOMAIN = $REALM
    $DOMAIN = $REALM
CONF

echo "[+] Wrote /etc/krb5.conf.d/$DOMAIN.conf"
echo "[*] DOMAIN=$DOMAIN  REALM=$REALM"
EOF
