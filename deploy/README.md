# Deployment naar Hetzner Cloud

Deze guide helpt je om Boerenbridge te deployen naar een Hetzner Cloud Server.

## Kosten

- **Server (CX22):** ~€4,51/maand
- **Domein (optioneel):** ~€10-15/jaar

## Vereisten

- [Hetzner Cloud account](https://console.hetzner.cloud)
- SSH key (voor veilige toegang)
- Optioneel: een domeinnaam

---

## Stap 1: SSH Key aanmaken (als je die nog niet hebt)

```bash
# Genereer een SSH key
ssh-keygen -t ed25519 -C "boerenbridge-hetzner"

# Kopieer je public key
cat ~/.ssh/id_ed25519.pub
```

## Stap 2: Hetzner Server aanmaken

1. Ga naar [console.hetzner.cloud](https://console.hetzner.cloud)
2. Maak een nieuw project aan (bijv. "Boerenbridge")
3. Klik op **"Add Server"**
4. Configuratie:
   - **Location:** Falkenstein (FSN1) of Nuremberg (NBG1) - Duitsland
   - **Image:** Ubuntu 24.04
   - **Type:** CX22 (2 vCPU, 4GB RAM, 40GB SSD)
   - **Networking:** Public IPv4 ✓, Public IPv6 ✓
   - **SSH Keys:** Voeg je public key toe
   - **Name:** `boerenbridge`
5. Klik **"Create & Buy Now"**

Noteer het **IP adres** van je server.

## Stap 3: Server configureren

Run het setup script op je nieuwe server:

```bash
# Maak scripts executable
chmod +x deploy/*.sh

# Setup de server (run dit lokaal, het stuurt commando's naar de server)
ssh root@<SERVER-IP> 'bash -s' < deploy/setup-server.sh
```

Het script vraagt of je een domein wilt gebruiken:
- **Met domein:** Voer je domein in (bijv. `boerenbridge.nl`) - je krijgt automatisch HTTPS
- **Zonder domein:** Druk Enter - je gebruikt dan het IP adres

## Stap 4: DNS instellen (alleen met domein)

Als je een domein hebt, stel dan een A-record in bij je domeinprovider:

| Type | Naam | Waarde |
|------|------|--------|
| A | @ | `<SERVER-IP>` |
| A | www | `<SERVER-IP>` |

## Stap 5: App deployen

```bash
# Deploy de app
./deploy/deploy.sh <SERVER-IP-OF-DOMEIN>

# Voorbeelden:
./deploy/deploy.sh 123.45.67.89
./deploy/deploy.sh boerenbridge.nl
```

---

## Dagelijks gebruik

### Nieuwe versie deployen

Na wijzigingen aan de code:

```bash
./deploy/deploy.sh <SERVER-IP-OF-DOMEIN>
```

### Server toegang

```bash
ssh root@<SERVER-IP>
```

### Logs bekijken

```bash
ssh root@<SERVER-IP> 'tail -f /var/log/nginx/access.log'
```

### SSL certificaat vernieuwen

Certbot vernieuwt automatisch, maar je kunt handmatig testen:

```bash
ssh root@<SERVER-IP> 'certbot renew --dry-run'
```

---

## Troubleshooting

### Site laadt niet

```bash
# Check of nginx draait
ssh root@<SERVER-IP> 'systemctl status nginx'

# Check firewall
ssh root@<SERVER-IP> 'ufw status'

# Check nginx error logs
ssh root@<SERVER-IP> 'tail -20 /var/log/nginx/error.log'
```

### SSL certificaat werkt niet

```bash
# Vraag nieuw certificaat aan
ssh root@<SERVER-IP> 'certbot --nginx -d <DOMEIN>'
```

### Rollback naar vorige versie

```bash
ssh root@<SERVER-IP> << 'EOF'
rm -rf /var/www/boerenbridge/*
cp -r /var/www/boerenbridge.backup/* /var/www/boerenbridge/
chown -R www-data:www-data /var/www/boerenbridge
EOF
```

---

## Beveiliging tips

1. **Disable root login** (na het aanmaken van een normale user):
   ```bash
   # Op de server
   adduser robin
   usermod -aG sudo robin
   # Kopieer SSH key naar nieuwe user
   ```

2. **Automatische updates**:
   ```bash
   ssh root@<SERVER-IP> 'apt install unattended-upgrades -y'
   ```

3. **Fail2ban** (bescherming tegen brute-force):
   ```bash
   ssh root@<SERVER-IP> 'apt install fail2ban -y && systemctl enable fail2ban'
   ```

---

## Kosten overzicht

| Item | Kosten |
|------|--------|
| Hetzner CX22 | €4,51/maand |
| Domein (.nl) | ~€10/jaar |
| SSL certificaat | Gratis (Let's Encrypt) |
| **Totaal** | **~€5/maand** |
