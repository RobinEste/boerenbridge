---
name: sessie-eind
description: Einde-sessie checklist en werklog bijwerken
user_invocable: true
---

# Sessie Eind

Voer de volgende stappen uit om de sessie netjes af te sluiten:

## Stappen

1. **Git status ophalen** — Voer parallel uit:
   - `git status`
   - `git diff --name-only`

2. **Kwaliteitscontrole** — Voer parallel uit (als er Dart-bestanden gewijzigd zijn):
   - `cd /Users/robin/Projects/Boerenbridge && flutter test`
   - `cd /Users/robin/Projects/Boerenbridge && flutter analyze`

   Als er geen Dart-wijzigingen zijn, sla deze stap over.

3. **Werklog bijwerken** — Vraag de gebruiker:
   - "Wat is de status van de huidige taak?" (voltooid / in progress / geparkeerd)
   - "Zijn er openstaande vragen of beslissingen om vast te leggen?"

   Werk `.claude/worklog.md` bij:
   - Update "Huidige Taak" op basis van het antwoord
   - Voeg nieuwe vragen/beslissingen toe indien genoemd
   - Voeg een rij toe aan sessie-historie (max 5 rijen bewaren, oudste verwijderen)
   - Gebruik de datum van vandaag

4. **Checklist tonen** — Toon deze checklist:

```
## Einde Sessie Checklist

- [ ] Alle wijzigingen gecommit
- [ ] Tests slagen (of n.v.t.)
- [ ] Analyze clean (of n.v.t.)
- [ ] Werklog bijgewerkt
- [ ] Gepusht naar `private` remote
```

5. **Push-herinnering** — Als er unpushed commits zijn, herinner:
   "Er zijn unpushed commits. Push naar `private` met: `git push private main`"
