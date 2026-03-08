# MCP Template Registry & Credential Flow — Implementierungsplan

> Detail-Referenz: [n8n-claw-implementierung.md](n8n-claw-implementierung.md) §2-3

Allgemeine n8n-claw Core-Features — Grundlage für beliebige Use Cases (Tourismus, Business, etc.).

## Übersicht

| Phase | Inhalt | Aufwand | Status |
|---|---|---|---|
| 1 | Template Registry + Library Manager | 8-12h | ✅ Done (v0.6.0) |
| 2 | Credential Flow (One-Time-Link) | 4-6h | Offen |

---

## Phase 1: MCP Template Registry & Library Manager ✅

> Umgesetzt in v0.6.0 (März 2026). Siehe [Release Notes](https://github.com/freddy-schuetz/n8n-claw/releases/tag/v0.6.0).

### Problem

MCP-Server werden aktuell manuell per MCP Builder erstellt. Kein Katalog, keine Wiederverwendung, kein "installiere mir das Weather-Tool".

### Ansatz

GitHub-Repo mit Template-Katalog + CDN (jsDelivr) + Library Manager Workflow in n8n.

Zwei Template-Typen (aktuell nur `native` implementiert):

| Typ | Beschreibung | Status |
|---|---|---|
| `native` | n8n implementiert Tool-Logik selbst (HTTP/Code Nodes) | ✅ |
| `bridge` | n8n leitet weiter: MCP Server Trigger → MCP Client → externer MCP Server | Offen |

### Tasks

#### 1.1 GitHub Repo anlegen

- [x] Repo `freddy-schuetz/n8n-claw-templates` erstellen
- [x] Verzeichnisstruktur: `templates/`
- [x] `templates/index.json` mit Katalog-Schema
- [x] `CLAUDE.md` für Template-Entwicklung
- [x] `TEMPLATE_EXAMPLE.md` als Referenz

#### 1.2 Templates erstellen

Statt des ursprünglich geplanten `weather-alpine` wurden 7 allgemeine Templates erstellt:

| Template ID | Name | API | Kategorie |
|---|---|---|---|
| `weather-openmeteo` | Weather (Open-Meteo) | api.open-meteo.com | weather |
| `wikipedia` | Wikipedia | wikipedia.org API | language |
| `dictionary` | Dictionary | dictionaryapi.dev | language |
| `exchange-rates` | Exchange Rates | frankfurter.app | utilities |
| `hackernews` | Hacker News | hn.algolia.com | news |
| `ip-geolocation` | IP Geolocation | ip-api.com | network |
| `website-check` | Website Check | (direkte HTTP-Aufrufe) | network |

- [x] Alle 7 Templates mit `manifest.json` + `workflow.json`
- [x] Zwei-Workflow-Pattern: `sub` (Tool-Logik) + `server` (MCP Trigger)
- [x] `REPLACE_SUB_WORKFLOW_ID` Placeholder-System
- [x] Alle Templates getestet und funktional

#### 1.3 CDN

- [x] jsDelivr-URL funktioniert (kein raw.githubusercontent.com — Rate Limits!)
- [ ] `.github/workflows/purge-cdn-cache.yml` — nicht implementiert, kein Blocker
- **Hinweis:** jsDelivr `@master` hat aggressives Caching (12-24h+). Workaround: `@{commit-hash}` in CDN_BASE verwenden. Live-Instance nutzt aktuell Commit-Hash statt `@master`.

#### 1.4 Library Manager Workflow

- [x] Neuer Workflow: `workflows/mcp-library-manager.json`
- [x] Tool: `list_templates` — index.json von CDN laden, optional filtern
- [x] Tool: `install_template` — Sub-Workflow importieren → ID patchen → Server-Workflow importieren → aktivieren → Registry-Eintrag
- [x] Tool: `remove_template` — Workflow deaktivieren + löschen + aus Registry entfernen
- [x] `mcp_registry` Tabelle erweitert
- [x] Als toolWorkflow im Agent-Workflow eingebunden
- Verifikation: Alle 7 Templates via Telegram installiert und getestet ✅

---

## Phase 2: Credential Flow (One-Time-Link)

### Problem

API-Keys im Chat austauschen ist unsicher (Telegram nicht E2E-verschlüsselt, Chat-Verlauf dauerhaft gespeichert).

### Ansatz

One-Time-Link mit 10 Min TTL → HTTPS-Formular (Passwort-Feld) → n8n Credentials API.

Flow:
1. User will Credential hinterlegen
2. Agent generiert UUID-Token (10 Min TTL) in PostgreSQL
3. Agent sendet HTTPS-Link zum Formular
4. User gibt Key im Passwort-Feld ein
5. n8n speichert Credential via API, invalidiert Token

### Tasks

#### 2.1 DB + Backend

- [ ] `credential_tokens` Tabelle erstellen (token UUID, template_id, cred_key, expires_at, used)
- [ ] PostgREST Grants
- Dateien: `supabase/migrations/001_schema.sql`
- Ref: Quelldatei §3.3

#### 2.2 Token + Formular

- [ ] Token-Generierung Code Node
- [ ] n8n Form Trigger: Formular mit Passwort-Feld
- [ ] Credential via n8n Credentials API speichern
- [ ] Token nach Nutzung invalidieren
- Verifikation: Link öffnen → Key eingeben → Credential in n8n sichtbar
- Ref: Quelldatei §3.4-3.5

#### 2.3 Integration mit Library Manager

- [ ] Nach `install_template` automatisch Credential Flow triggern wenn `credentials_required` im Manifest
- Verifikation: "Installiere google-reviews" → Template installiert + Credential-Link gesendet
