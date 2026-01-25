#!/bin/bash
# =============================================================================
# Hetzner Server Setup Script voor Boerenbridge
# Run dit eenmalig op je nieuwe Hetzner server
# Usage: ssh root@<server-ip> 'bash -s' < setup-server.sh
# =============================================================================

set -e  # Stop bij errors

# Kleuren voor output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Boerenbridge Server Setup ===${NC}"

# Vraag om domein (optioneel)
read -p "Voer je domein in (of laat leeg voor alleen IP): " DOMAIN

# =============================================================================
# 1. System updates
# =============================================================================
echo -e "${YELLOW}[1/5] Systeem updaten...${NC}"
apt update && apt upgrade -y

# =============================================================================
# 2. Installeer benodigde packages
# =============================================================================
echo -e "${YELLOW}[2/5] Nginx en tools installeren...${NC}"
apt install -y nginx certbot python3-certbot-nginx ufw

# =============================================================================
# 3. Firewall configureren
# =============================================================================
echo -e "${YELLOW}[3/5] Firewall configureren...${NC}"
ufw allow OpenSSH
ufw allow 'Nginx Full'
ufw --force enable

# =============================================================================
# 4. Nginx configureren
# =============================================================================
echo -e "${YELLOW}[4/5] Nginx configureren...${NC}"

# Maak web directory
mkdir -p /var/www/boerenbridge
chown -R www-data:www-data /var/www/boerenbridge

# Nginx config
if [ -n "$DOMAIN" ]; then
    SERVER_NAME="$DOMAIN"
else
    SERVER_NAME="_"
fi

cat > /etc/nginx/sites-available/boerenbridge << 'NGINX_CONFIG'
server {
    listen 80;
    listen [::]:80;
    server_name SERVER_NAME_PLACEHOLDER;

    root /var/www/boerenbridge;
    index index.html;

    # Gzip compressie voor betere performance
    gzip on;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml text/javascript application/wasm;
    gzip_min_length 1000;

    # Cache static assets
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }

    # Flutter web app - SPA routing
    location / {
        try_files $uri $uri/ /index.html;
    }

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
}
NGINX_CONFIG

# Vervang placeholder met echte server name
sed -i "s/SERVER_NAME_PLACEHOLDER/$SERVER_NAME/" /etc/nginx/sites-available/boerenbridge

# Activeer de site
ln -sf /etc/nginx/sites-available/boerenbridge /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

# Test nginx config
nginx -t

# Herstart nginx
systemctl restart nginx
systemctl enable nginx

# =============================================================================
# 5. SSL certificaat (alleen als domein is opgegeven)
# =============================================================================
if [ -n "$DOMAIN" ]; then
    echo -e "${YELLOW}[5/5] SSL certificaat aanvragen...${NC}"
    certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos --email admin@"$DOMAIN" --redirect
else
    echo -e "${YELLOW}[5/5] Geen domein opgegeven, SSL overgeslagen${NC}"
    echo -e "${YELLOW}    Je kunt later SSL toevoegen met: certbot --nginx -d <domein>${NC}"
fi

# =============================================================================
# Klaar!
# =============================================================================
echo ""
echo -e "${GREEN}=== Setup Compleet! ===${NC}"
echo ""
if [ -n "$DOMAIN" ]; then
    echo -e "Je site is bereikbaar op: ${GREEN}https://$DOMAIN${NC}"
else
    IP=$(curl -s ifconfig.me)
    echo -e "Je site is bereikbaar op: ${GREEN}http://$IP${NC}"
fi
echo ""
echo -e "Upload je Flutter build met:"
echo -e "  ${YELLOW}./deploy.sh <server-ip>${NC}"
echo ""
