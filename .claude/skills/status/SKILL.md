---
name: status
description: Compact overzicht van huidige taak en git status
user_invocable: true
---

# Status

Lichtgewicht statusoverzicht. Voer uit:

## Stappen

1. **Git info ophalen** — Voer parallel uit:
   - `git status --short`
   - `git log --oneline -5`

2. **Werklog lezen** — Lees `.claude/worklog.md`.

3. **Compact overzicht tonen** — Geef output in dit formaat:

```
## Status

**Taak:** [huidige taak uit werklog, of "Geen actieve taak"]
**Status:** [status uit werklog]
**Volgende stap:** [volgende stap uit werklog]

**Git:** [branch] | [aantal uncommitted changes of "clean"]
**Laatste commits:**
- [commit 1]
- [commit 2]
- [commit 3]
```
