# Werklog

## Huidige Taak

- **Beschrijving:** Server hardening n.a.v. AI-Readiness-Audit incident (issue #52)
- **Status:** In progress
- **Volgende stap:** Nginx security headers fix (location block inheritance), Hetzner Cloud Firewall, uptime monitoring

## Openstaande Vragen

- Welk IP-bereik toestaan voor SSH in Hetzner Cloud Firewall? (eigen IP / kantoor IP)
- Nginx headers fix + missende sudoers regel (`systemctl reload nginx`) vereisen rescue mode of root toegang

## Recente Beslissingen

- Deploy workflow omgezet van appleboy/scp-action naar rsync (single SSH connection, voorkomt UFW rate limit blocks)
- Deploy user `deploy` i.p.v. root voor alle server operaties
- UFW SSH rate limiting actief (werkt goed met rsync, blokkeerde scp-action)

## Sessie-historie

| Datum | Taak | Resultaat |
|-------|------|-----------|
| 2026-02-04 | Server hardening (12 stappen) | 9/11 roadmap items afgerond. Server: SSH hardening, fail2ban, kernel sysctl, /tmp noexec, unattended-upgrades, auditd actief. CI/CD: SHA pinning, server IP secret, deploy user, rsync deploy. Open: nginx headers, Hetzner Cloud Firewall, uptime monitoring. |
