# Werklog

## Huidige Taak

- **Beschrijving:** Server hardening n.a.v. AI-Readiness-Audit incident (issue #52)
- **Status:** In progress
- **Volgende stap:** Nginx security headers fix (location block inheritance), Hetzner Cloud Firewall, uptime monitoring

## Openstaande Vragen

- Welk IP-bereik toestaan voor SSH in Hetzner Cloud Firewall? (eigen IP / kantoor IP)
- Nginx headers fix + missende sudoers regel (`systemctl reload nginx`) vereisen rescue mode

## Recente Beslissingen

- Deploy workflow omgezet van appleboy/scp-action naar rsync (single SSH connection, voorkomt UFW rate limit blocks)
- Deploy user `deploy` i.p.v. root voor alle server operaties
- Deploy script moet eerst `chown deploy:www-data` doen op /var/www/boerenbridge, dan cp, dan `chown www-data:www-data` terug

## Sessie-historie

| Datum | Taak | Resultaat |
|-------|------|-----------|
| 2026-02-04 | Server hardening + deploy pipeline | 9/11 roadmap items afgerond. Server: SSH hardening, fail2ban, kernel sysctl, /tmp noexec, unattended-upgrades, auditd. CI/CD: SHA pinning, server IP secret, deploy user, rsync deploy. Deploy pipeline werkend na 4 iteraties (permission + rate limit fixes). Open: nginx headers, Hetzner Cloud Firewall, uptime monitoring. |
