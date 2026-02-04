---
name: sessie-start
description: Laadt projectcontext bij start van een werksessie
user_invocable: true
---

# Sessie Start

Voer de volgende stappen uit om de sessie op te starten:

## Stappen

1. **Werklog laden** — Lees `.claude/worklog.md` volledig en onthoud de inhoud.

2. **Roadmap laden** — Lees `README.md` regels 181-212 (roadmap sectie).

3. **Git status ophalen** — Voer parallel uit:
   - `git status`
   - `git log --oneline -10`

4. **Samenvatting tonen** — Geef de gebruiker een overzicht in dit formaat:

```
## Sessie Gestart

### Werkcontext
[Huidige taak uit werklog, of "Geen actieve taak"]

### Openstaande Vragen
[Uit werklog, of "Geen"]

### Recente Beslissingen
[Uit werklog, of "Geen"]

### Git Status
[Kort: branch, uncommitted changes, laatste 3 commits]

### Roadmap (te doen)
[Openstaande items uit README roadmap]
```

5. **Vraag** — Vraag de gebruiker: "Waar wil je deze sessie aan werken?"
