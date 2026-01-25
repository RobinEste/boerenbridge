#!/bin/bash
# =============================================================================
# Deploy Script voor Boerenbridge naar Hetzner
# Run dit lokaal om de app te builden en uploaden
# Usage: ./deploy.sh <server-ip-of-domein> [ssh-user]
# =============================================================================

set -e  # Stop bij errors

# Kleuren voor output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# =============================================================================
# Argumenten checken
# =============================================================================
if [ -z "$1" ]; then
    echo -e "${RED}Error: Geen server opgegeven${NC}"
    echo "Usage: ./deploy.sh <server-ip-of-domein> [ssh-user]"
    echo "Voorbeeld: ./deploy.sh 123.45.67.89"
    echo "Voorbeeld: ./deploy.sh boerenbridge.nl root"
    exit 1
fi

SERVER="$1"
SSH_USER="${2:-root}"
REMOTE_PATH="/var/www/boerenbridge"

# Ga naar project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

echo -e "${GREEN}=== Boerenbridge Deployment ===${NC}"
echo -e "Server: ${YELLOW}$SERVER${NC}"
echo -e "User: ${YELLOW}$SSH_USER${NC}"
echo ""

# =============================================================================
# 1. Flutter build
# =============================================================================
echo -e "${YELLOW}[1/4] Flutter web build maken...${NC}"

# Check of flutter beschikbaar is
if ! command -v flutter &> /dev/null; then
    echo -e "${RED}Error: Flutter is niet geïnstalleerd of niet in PATH${NC}"
    exit 1
fi

# Build
flutter build web --release

if [ ! -d "build/web" ]; then
    echo -e "${RED}Error: Build directory niet gevonden${NC}"
    exit 1
fi

echo -e "${GREEN}Build succesvol!${NC}"

# =============================================================================
# 2. Comprimeer build voor snellere upload
# =============================================================================
echo -e "${YELLOW}[2/4] Build comprimeren...${NC}"

cd build
tar -czf web.tar.gz web/
cd ..

BUILD_SIZE=$(du -h build/web.tar.gz | cut -f1)
echo -e "Build grootte: ${GREEN}$BUILD_SIZE${NC}"

# =============================================================================
# 3. Upload naar server
# =============================================================================
echo -e "${YELLOW}[3/4] Uploaden naar server...${NC}"

# Upload tar
scp build/web.tar.gz "$SSH_USER@$SERVER:/tmp/"

# =============================================================================
# 4. Deploy op server
# =============================================================================
echo -e "${YELLOW}[4/4] Deployen op server...${NC}"

ssh "$SSH_USER@$SERVER" << 'REMOTE_COMMANDS'
set -e

# Backup huidige versie (indien aanwezig)
if [ -d "/var/www/boerenbridge" ] && [ "$(ls -A /var/www/boerenbridge 2>/dev/null)" ]; then
    echo "Backup maken van huidige versie..."
    rm -rf /var/www/boerenbridge.backup
    cp -r /var/www/boerenbridge /var/www/boerenbridge.backup
fi

# Extract nieuwe versie
echo "Nieuwe versie uitpakken..."
cd /tmp
tar -xzf web.tar.gz

# Deploy
rm -rf /var/www/boerenbridge/*
cp -r web/* /var/www/boerenbridge/

# Permissies
chown -R www-data:www-data /var/www/boerenbridge

# Cleanup
rm -f /tmp/web.tar.gz
rm -rf /tmp/web

echo "Deploy compleet!"
REMOTE_COMMANDS

# Cleanup lokaal
rm -f build/web.tar.gz

# =============================================================================
# Klaar!
# =============================================================================
echo ""
echo -e "${GREEN}=== Deployment Succesvol! ===${NC}"
echo ""

# Probeer te bepalen of het een IP of domein is
if [[ $SERVER =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo -e "Je app is live op: ${GREEN}http://$SERVER${NC}"
else
    echo -e "Je app is live op: ${GREEN}https://$SERVER${NC}"
fi

echo ""
echo -e "Tip: Test de app door de URL in je browser te openen!"
