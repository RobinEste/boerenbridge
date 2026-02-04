#!/bin/bash
# =============================================================================
# Hetzner Server Setup Script voor Lekkerkaarten (Boerenbridge)
# Run dit eenmalig op je nieuwe Hetzner server
# Usage: ssh root@<server-ip> 'bash -s' < setup-server.sh
#
# Dit script configureert:
#   1. System updates
#   2. Deploy user (geen root deploys)
#   3. SSH hardening (geen password auth, geen root login)
#   4. Fail2ban (brute-force bescherming)
#   5. Firewall (UFW met rate limiting)
#   6. Kernel hardening (sysctl)
#   7. /tmp noexec (voorkomt malware executie)
#   8. Nginx met security headers
#   9. SSL certificaat (Let's Encrypt)
#  10. Unattended-upgrades (automatische security patches)
#  11. auditd (server audit trail)
# =============================================================================

set -e  # Stop bij errors

# Kleuren voor output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

TOTAL_STEPS=11

echo -e "${GREEN}=== Lekkerkaarten Server Setup ===${NC}"
echo ""

# Vraag om domein (optioneel)
read -p "Voer je domein in (of laat leeg voor alleen IP): " DOMAIN

# =============================================================================
# 1. System updates
# =============================================================================
echo -e "${YELLOW}[1/$TOTAL_STEPS] Systeem updaten...${NC}"
apt update && apt upgrade -y

# =============================================================================
# 2. Deploy user aanmaken
# =============================================================================
echo -e "${YELLOW}[2/$TOTAL_STEPS] Deploy user aanmaken...${NC}"

if id "deploy" &>/dev/null; then
    echo "User 'deploy' bestaat al, overgeslagen"
else
    useradd -m -s /bin/bash deploy
    mkdir -p /home/deploy/.ssh
    chmod 700 /home/deploy/.ssh

    # Kopieer authorized_keys van root naar deploy user
    if [ -f /root/.ssh/authorized_keys ]; then
        cp /root/.ssh/authorized_keys /home/deploy/.ssh/authorized_keys
        chmod 600 /home/deploy/.ssh/authorized_keys
        chown -R deploy:deploy /home/deploy/.ssh
        echo "SSH keys gekopieerd van root naar deploy"
    else
        echo -e "${RED}Let op: geen authorized_keys gevonden voor root${NC}"
        echo "Voeg handmatig een SSH key toe: /home/deploy/.ssh/authorized_keys"
    fi

    # Deploy user mag web directory beheren en nginx herladen
    cat > /etc/sudoers.d/deploy << 'SUDOERS'
deploy ALL=(ALL) NOPASSWD: /bin/chown -R www-data\:www-data /var/www/boerenbridge
deploy ALL=(ALL) NOPASSWD: /bin/chown -R www-data\:www-data /var/www/boerenbridge/*
deploy ALL=(ALL) NOPASSWD: /usr/sbin/nginx -t
deploy ALL=(ALL) NOPASSWD: /bin/systemctl reload nginx
SUDOERS
    chmod 440 /etc/sudoers.d/deploy

    echo "User 'deploy' aangemaakt met beperkte sudo rechten"
fi

# Web directory eigenaarschap
mkdir -p /var/www/boerenbridge
chown -R www-data:www-data /var/www/boerenbridge
# Deploy user moet bestanden kunnen schrijven
usermod -aG www-data deploy

# =============================================================================
# 3. Installeer benodigde packages
# =============================================================================
echo -e "${YELLOW}[3/$TOTAL_STEPS] Packages installeren...${NC}"
apt install -y nginx certbot python3-certbot-nginx ufw \
    fail2ban auditd unattended-upgrades apt-listchanges

# =============================================================================
# 4. SSH hardening
# =============================================================================
echo -e "${YELLOW}[4/$TOTAL_STEPS] SSH hardening...${NC}"

SSHD_CONFIG="/etc/ssh/sshd_config"

# Backup originele config
cp "$SSHD_CONFIG" "${SSHD_CONFIG}.backup.$(date +%Y%m%d)"

# Hardening instellingen toepassen
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' "$SSHD_CONFIG"
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' "$SSHD_CONFIG"
sed -i 's/^#\?MaxAuthTries.*/MaxAuthTries 3/' "$SSHD_CONFIG"
sed -i 's/^#\?X11Forwarding.*/X11Forwarding no/' "$SSHD_CONFIG"
sed -i 's/^#\?PermitEmptyPasswords.*/PermitEmptyPasswords no/' "$SSHD_CONFIG"

# Voeg toe als ze niet bestaan
grep -q "^PasswordAuthentication" "$SSHD_CONFIG" || echo "PasswordAuthentication no" >> "$SSHD_CONFIG"
grep -q "^PermitRootLogin" "$SSHD_CONFIG" || echo "PermitRootLogin no" >> "$SSHD_CONFIG"
grep -q "^MaxAuthTries" "$SSHD_CONFIG" || echo "MaxAuthTries 3" >> "$SSHD_CONFIG"

# Valideer config voordat we herstarten
sshd -t && systemctl restart sshd
echo "SSH gehardend: geen password auth, geen root login, max 3 pogingen"

# =============================================================================
# 5. Fail2ban configureren
# =============================================================================
echo -e "${YELLOW}[5/$TOTAL_STEPS] Fail2ban configureren...${NC}"

cat > /etc/fail2ban/jail.local << 'FAIL2BAN'
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 3
banaction = ufw

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600
findtime = 600

[nginx-http-auth]
enabled = true
port = http,https
filter = nginx-http-auth
logpath = /var/log/nginx/error.log
maxretry = 5
bantime = 3600

[nginx-limit-req]
enabled = true
port = http,https
filter = nginx-limit-req
logpath = /var/log/nginx/error.log
maxretry = 10
bantime = 600
FAIL2BAN

systemctl enable fail2ban
systemctl restart fail2ban
echo "Fail2ban actief: SSH (3 pogingen/10min → 1 uur ban)"

# =============================================================================
# 6. Firewall configureren
# =============================================================================
echo -e "${YELLOW}[6/$TOTAL_STEPS] Firewall configureren...${NC}"

ufw --force reset
ufw default deny incoming
ufw default allow outgoing

# SSH met rate limiting (max 6 connecties per 30 sec per IP)
ufw limit OpenSSH

# HTTP/HTTPS
ufw allow 'Nginx Full'

ufw --force enable
echo "UFW actief: SSH (rate limited), HTTP, HTTPS"

# =============================================================================
# 7. Kernel sysctl hardening
# =============================================================================
echo -e "${YELLOW}[7/$TOTAL_STEPS] Kernel hardening...${NC}"

cat > /etc/sysctl.d/99-security.conf << 'SYSCTL'
# SYN flood protection
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 2048
net.ipv4.tcp_synack_retries = 2

# Anti-spoofing (reverse path filtering)
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# Geen ICMP redirects accepteren (voorkomt MITM)
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0

# Geen source routing
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0

# Log verdachte pakketten
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1

# ICMP hardening
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1

# IPv6 hardening (als niet in gebruik)
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv6.conf.default.accept_source_route = 0
SYSCTL

sysctl --system > /dev/null 2>&1
echo "Kernel gehardend: SYN flood, anti-spoofing, ICMP, no redirects"

# =============================================================================
# 8. /tmp noexec mount
# =============================================================================
echo -e "${YELLOW}[8/$TOTAL_STEPS] /tmp noexec configureren...${NC}"

# Gebruik tmpfs met noexec voor /tmp
if ! grep -q "tmpfs.*/tmp" /etc/fstab; then
    echo "tmpfs /tmp tmpfs defaults,noexec,nosuid,nodev,size=512M 0 0" >> /etc/fstab
    # Pas direct toe (verplaats bestaande bestanden)
    mkdir -p /tmp.backup
    cp -a /tmp/* /tmp.backup/ 2>/dev/null || true
    mount -o remount /tmp 2>/dev/null || mount /tmp
    cp -a /tmp.backup/* /tmp/ 2>/dev/null || true
    rm -rf /tmp.backup
    echo "/tmp gemount met noexec,nosuid,nodev (512MB tmpfs)"
else
    echo "/tmp noexec al geconfigureerd, overgeslagen"
fi

# =============================================================================
# 9. Nginx configureren
# =============================================================================
echo -e "${YELLOW}[9/$TOTAL_STEPS] Nginx configureren...${NC}"

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

    # Geen cache voor HTML en Flutter bootstrap bestanden (altijd vers)
    location ~* (index\.html|flutter_bootstrap\.js|flutter_service_worker\.js|version\.json|manifest\.json)$ {
        expires -1;
        add_header Cache-Control "no-store, no-cache, must-revalidate";
    }

    # Cache static assets (gehashte bestanden kunnen lang gecached)
    location ~* \.(css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }

    # JavaScript: korte cache zodat updates snel doorkomen
    location ~* \.js$ {
        expires 1h;
        add_header Cache-Control "public, max-age=3600";
    }

    # Flutter web app - SPA routing
    location / {
        try_files $uri $uri/ /index.html;
    }

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header Permissions-Policy "camera=(), microphone=(), geolocation=(), payment=()" always;
    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains" always;
    add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; font-src 'self' https://fonts.gstatic.com; connect-src 'self' https://*.supabase.co wss://*.supabase.co; img-src 'self' data: blob:; worker-src 'self' blob:; frame-ancestors 'self'" always;
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
# 10. SSL certificaat (alleen als domein is opgegeven)
# =============================================================================
if [ -n "$DOMAIN" ]; then
    echo -e "${YELLOW}[10/$TOTAL_STEPS] SSL certificaat aanvragen...${NC}"
    certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos --email admin@"$DOMAIN" --redirect
else
    echo -e "${YELLOW}[10/$TOTAL_STEPS] Geen domein opgegeven, SSL overgeslagen${NC}"
    echo -e "${YELLOW}    Je kunt later SSL toevoegen met: certbot --nginx -d <domein>${NC}"
fi

# =============================================================================
# 11. Unattended-upgrades configureren
# =============================================================================
echo -e "${YELLOW}[11/$TOTAL_STEPS] Unattended-upgrades configureren...${NC}"

cat > /etc/apt/apt.conf.d/50unattended-upgrades << 'UNATTENDED'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
    "${distro_id}ESMApps:${distro_codename}-apps-security";
    "${distro_id}ESM:${distro_codename}-infra-security";
};

Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
UNATTENDED

cat > /etc/apt/apt.conf.d/20auto-upgrades << 'AUTOUPGRADE'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
AUTOUPGRADE

echo "Unattended-upgrades actief: dagelijkse security patches"

# =============================================================================
# 12. auditd configureren
# =============================================================================
echo -e "${YELLOW}[bonus] auditd configureren...${NC}"

systemctl enable auditd
systemctl start auditd

# Audit regels voor security-relevante events
cat > /etc/audit/rules.d/security.rules << 'AUDIT'
# Bestands- en accountwijzigingen monitoren
-w /etc/passwd -p wa -k user_changes
-w /etc/shadow -p wa -k password_changes
-w /etc/sudoers -p wa -k sudoers_changes
-w /etc/ssh/sshd_config -p wa -k ssh_config
-w /var/www/boerenbridge -p wa -k web_changes

# Authenticatiepogingen
-w /var/log/auth.log -p r -k auth_log_access

# Cron en systemd wijzigingen
-w /etc/crontab -p wa -k cron_changes
-w /etc/cron.d -p wa -k cron_changes
-w /etc/systemd -p wa -k systemd_changes
AUDIT

augenrules --load > /dev/null 2>&1
echo "auditd actief: monitort SSH, users, web directory, cron"

# =============================================================================
# Klaar!
# =============================================================================
echo ""
echo -e "${GREEN}=== Setup Compleet! ===${NC}"
echo ""
echo -e "${GREEN}Beveiligingsmaatregelen actief:${NC}"
echo "  - SSH: geen password auth, geen root login, max 3 pogingen"
echo "  - Fail2ban: brute-force bescherming op SSH en Nginx"
echo "  - UFW: alleen SSH (rate limited), HTTP, HTTPS"
echo "  - Kernel: SYN flood, anti-spoofing, ICMP hardening"
echo "  - /tmp: noexec (voorkomt malware executie)"
echo "  - Nginx: CSP, HSTS, Permissions-Policy headers"
echo "  - Unattended-upgrades: dagelijkse security patches"
echo "  - auditd: server audit trail"
echo ""
echo -e "${YELLOW}Belangrijk:${NC}"
echo "  - Deploy user: 'deploy' (gebruik deze i.p.v. root)"
echo "  - Update je GitHub Actions SSH_PRIVATE_KEY secret voor de deploy user"
echo "  - Configureer een Hetzner Cloud Firewall (zie README)"
echo ""
if [ -n "$DOMAIN" ]; then
    echo -e "Je site is bereikbaar op: ${GREEN}https://$DOMAIN${NC}"
else
    IP=$(curl -s ifconfig.me)
    echo -e "Je site is bereikbaar op: ${GREEN}http://$IP${NC}"
fi
echo ""
