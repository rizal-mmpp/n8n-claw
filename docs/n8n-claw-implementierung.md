# n8n-claw Tourismus-Plattform
## Vollständige Implementierungsdokumentation

**MCP Template Registry · Library Manager · Credential Flow · Tourismus-MCP-Server · DMO-Use Case in One.Intelligence**

> Für Claude Code — Schritt-für-Schritt-Umsetzung  
> Version 1.0 · März 2026 · Friedemann Schuetz

---

## Inhaltsverzeichnis

1. [Systemarchitektur & Überblick](#1-systemarchitektur--überblick)
2. [Phase 1: MCP Template Registry & Library Manager](#2-phase-1-mcp-template-registry--library-manager)
3. [Phase 2: Credential Flow (One-Time-Link)](#3-phase-2-credential-flow-one-time-link)
4. [Phase 3: Tourismus-MCP-Server](#4-phase-3-tourismus-mcp-server)
5. [Phase 4: DMO-Datenbank & Multi-User-Setup](#5-phase-4-dmo-datenbank--multi-user-setup)
6. [Phase 5: One.Intelligence Integration](#6-phase-5-oneintelligence-integration)
7. [Phase 6: Proaktives Briefing & Scheduling](#7-phase-6-proaktives-briefing--scheduling)
8. [DMO Use Case: Dialogbeispiele](#8-dmo-use-case-dialogbeispiele)
9. [Alleinstellungsmerkmal vs. Standard-Webhook-Agent](#9-alleinstellungsmerkmal-vs-standard-webhook-agent)
10. [Implementierungsreihenfolge für Claude Code](#10-implementierungsreihenfolge-für-claude-code)

---

## 1. Systemarchitektur & Überblick

Dieses Dokument beschreibt die vollständige Umsetzung der n8n-claw Tourismus-Plattform — von der Infrastruktur bis zur Nutzererfahrung in One.Intelligence. Alle Phasen sind als aufeinander aufbauende, mit Claude Code umsetzbare Schritte strukturiert.

> **Leitprinzip:** "Alles per Chat, nie in die n8n-UI" — Sandra und Thomas bedienen den gesamten Stack ausschließlich über das One.Intelligence-Chatfenster. Der Agent erweitert sich selbst, lernt aus Gesprächen und wird proaktiv.

### Gesamtarchitektur

```
one.intelligence (oi.destination.one)
  └── Modell "DMO-Operationsassistent"
        └── Pipe Function (Python) → HTTPS → n8n Webhook
              └── n8n-claw Agent Workflow
                    ├── PostgreSQL (Memory: soul, conversations, memory_long)
                    ├── MCP Client → MCP Registry
                    │     ├── weather-alpine   (Open-Meteo, kostenlos)
                    │     ├── google-reviews   (Places API)
                    │     ├── social-post      (Instagram Graph API)
                    │     ├── member-db        (interne Postgres-Tabelle)
                    │     └── email-sender     (SMTP)
                    ├── MCP Builder  ← erstellt neue MCP-Server per Chat
                    └── ReminderFactory  ← proaktive Briefings (Cron)
```

### Phasen-Übersicht

| Phase | Inhalt | Aufwand | Status |
|-------|--------|---------|--------|
| Phase 1 | MCP Template Registry & Library Manager | 8–12 h | ✅ Done (v0.6.0) |
| Phase 2 | Credential Flow (One-Time-Link) | 4–6 h | Offen |
| Phase 3 | Tourismus-MCP-Server | 10–16 h | Offen |
| Phase 4 | DMO-Datenbank & Multi-User | 6–8 h | Offen |
| Phase 5 | One.Intelligence Integration | 4–6 h | Offen |
| Phase 6 | Proaktives Briefing & Scheduling | 4–6 h | Offen |

---

## 2. Phase 1: MCP Template Registry & Library Manager ✅

> Umgesetzt in v0.6.0 (März 2026). Details: [template-registry.md](template-registry.md)

### 2.1 Repository-Struktur (GitHub)

Öffentliches Repository: [`freddy-schuetz/n8n-claw-templates`](https://github.com/freddy-schuetz/n8n-claw-templates)

```
n8n-claw-templates/
├── templates/
│   ├── index.json                    ← zentraler Katalog (7 Templates)
│   ├── TEMPLATE_EXAMPLE.md           ← Referenz für neue Templates
│   ├── weather-openmeteo/            ← Typ: native
│   │   ├── manifest.json
│   │   └── workflow.json
│   ├── wikipedia/
│   ├── dictionary/
│   ├── exchange-rates/
│   ├── hackernews/
│   ├── ip-geolocation/
│   └── website-check/
├── CLAUDE.md                         ← Entwicklerdoku für AI-Assistenten
└── README.md
```

> **Hinweis:** Jedes Template besteht aus `manifest.json` + `workflow.json` (Zwei-Workflow-Bundle: sub + server). Bridge-Templates sind konzeptionell definiert aber noch nicht implementiert.

### 2.2 Template-Typen

Es gibt zwei grundlegend unterschiedliche Template-Typen:

| Typ | Beschreibung | Beispiele | Status |
|-----|--------------|-----------|--------|
| `native` | n8n implementiert die Tool-Logik selbst (Code Nodes mit `helpers.httpRequest()`) | weather-openmeteo, wikipedia, dictionary, exchange-rates, hackernews, ip-geolocation, website-check | ✅ 7 Templates |
| `bridge` | n8n leitet nur weiter: MCP Server Trigger → MCP Client Tool → externer MCP Server | (geplant: dzt-knowledge-graph, bayerncloud-events) | Offen |

**Zwei-Workflow-Pattern (sub + server):**

Jedes native Template besteht aus zwei Workflows in einer `workflow.json`-Datei:
- **`sub`**: Sub-Workflow mit der eigentlichen Tool-Logik (`executeWorkflowTrigger` → `Code` Node)
- **`server`**: MCP Server Workflow (`mcpTrigger` → `toolWorkflow` mit `REPLACE_SUB_WORKFLOW_ID`)

**Warum zwei Workflows?** n8n's API ignoriert `specifyInputSchema` beim Erstellen von Workflows. Das `toolWorkflow` + Sub-Workflow Pattern umgeht diesen Bug — Parameter kommen via `$json.param` an, was immer funktioniert.

```
n8n-claw Agent
  └── MCP Client Tool → MCP Server Workflow (mcpTrigger)
                              └── toolWorkflow → Sub-Workflow (Code Node)
                                                    └── helpers.httpRequest() → externe API
```

### 2.3 Manifest-Format

Jedes Template hat eine `manifest.json`:

```json
{
  "id": "weather-openmeteo",
  "name": "Weather (Open-Meteo)",
  "version": "1.0.0",
  "updated": "2026-03-08",
  "type": "native",
  "category": "weather",
  "description": "Current weather and 7-day forecast for any city worldwide (Open-Meteo, free, no API key)",
  "credentials_required": [],
  "credentials_optional": [],
  "tools": [
    { "name": "get_weather", "description": "Get current weather and 7-day forecast for any city" }
  ],
  "author": "freddy-schuetz",
  "license": "MIT",
  "tested_n8n_version": "2.10.4"
}
```

### 2.4 index.json — zentraler Katalog

Der Katalog enthält aktuell 7 allgemeine Templates (alle `native`, keine Credentials nötig):

```json
{
  "version": "1",
  "updated": "2026-03-08",
  "templates": [
    { "id": "weather-openmeteo", "name": "Weather (Open-Meteo)", "type": "native", "category": "weather" },
    { "id": "wikipedia", "name": "Wikipedia", "type": "native", "category": "language" },
    { "id": "dictionary", "name": "Dictionary", "type": "native", "category": "language" },
    { "id": "exchange-rates", "name": "Exchange Rates", "type": "native", "category": "utilities" },
    { "id": "hackernews", "name": "Hacker News", "type": "native", "category": "news" },
    { "id": "ip-geolocation", "name": "IP Geolocation", "type": "native", "category": "network" },
    { "id": "website-check", "name": "Website Check", "type": "native", "category": "network" }
  ]
}
```

> **Anmerkung:** Die ursprünglich geplanten Tourismus-Templates (google-reviews, instagram-post, dzt-knowledge-graph, bayerncloud-events) sind in Phase 3 vorgesehen und noch nicht umgesetzt.

### 2.4 CDN-Strategie: jsDelivr ✅

> ⚠️ **raw.githubusercontent.com NICHT verwenden** — seit Mai 2025 drastisch verschärfte Rate Limits (HTTP 429).

```
# URL-Schema jsDelivr:
https://cdn.jsdelivr.net/gh/freddy-schuetz/n8n-claw-templates@{ref}/templates/index.json

# WICHTIG: @master hat aggressives Caching (12-24h+), Purge unzuverlässig.
# Workaround: @{commit-hash} verwenden für sofortige Updates.
# Beispiel:
https://cdn.jsdelivr.net/gh/freddy-schuetz/n8n-claw-templates@6b3edf3/templates/index.json
```

> **CDN Cache Purge GitHub Action:** Nicht implementiert — kein Blocker, da Commit-Hash-Referenz das Problem umgeht.

### 2.5 Library Manager Workflow in n8n ✅

Workflow **"MCP Library Manager"** mit drei Tools:

- **`list_templates`** — Lädt `index.json` von jsDelivr, optional nach Kategorie filtern
- **`install_template`** — Zwei-Schritt-Import: Sub-Workflow importieren → ID in Server-Workflow patchen → Server importieren → aktivieren → `mcp_registry` Eintrag erstellen
- **`remove_template`** — Beide Workflows (Sub + Server) deaktivieren, löschen, Registry-Eintrag entfernen

**Wichtige Implementierungsdetails:**
- Verwendet `helpers.httpRequest()` (nicht `$helpers` — funktioniert nicht in Code Node v2)
- `REPLACE_SUB_WORKFLOW_ID` wird zur Install-Zeit mit der echten Sub-Workflow-ID ersetzt
- Aktivierung erfolgt automatisch mit Retry bei Rate Limits
- CDN_BASE zeigt auf jsDelivr mit Commit-Hash für zuverlässiges Caching

### 2.6 Bridge-Workflow: Aufbau und Konfiguration (noch nicht implementiert)

Ein Bridge-Workflow besteht aus genau zwei Nodes:

```
[MCP Server Trigger] → [MCP Client Tool]
```

Der MCP Server Trigger exponiert die Tools nach oben (zum n8n-claw Agent). Der MCP Client Tool ruft den externen MCP Server an und leitet Requests und Responses durch.

#### Beispiel: dzt-knowledge-graph Bridge

**Node 1 — MCP Server Trigger**
```
Type:           MCP Server Trigger
Workflow Name:  DZT Knowledge Graph Bridge
```
Keine weitere Konfiguration nötig — der Trigger exponiert automatisch alle Tools, die der MCP Client nach unten weiterreicht.

**Node 2 — MCP Client Tool**
```
Type:           MCP Client (Tools)
Connection:     SSE / HTTP
URL:            https://proxy.opendatagermany.io/mcp
Auth Header:    x-api-key: {{ $env.DZT_API_KEY }}
```

> ⚠️ **DZT MCP Status:** Die DZT-Entwicklerdokumentation führt MCP als eigene Sektion — der Endpoint ist aber Login-gesperrt. API-Key per E-Mail an open-data@germany.travel anfordern und MCP-URL verifizieren. Falls kein SSE-Endpoint verfügbar ist, kann der Bridge-Workflow stattdessen die REST-API (`proxy.opendatagermany.io/api/ts/v2/kg/`) über normale HTTP Nodes ansprechen — dann ist es faktisch ein natives Template.

#### Beispiel: bayerncloud-events Bridge (stdio — Sonderfall)

Der BayernCloud MCP Server (github.com/BayernTourismus/mcp-server) läuft als lokaler Node.js-Prozess (stdio-Transport). Das erfordert einen HTTP-Wrapper auf dem n8n-Server:

```bash
# Auf dem n8n-Server: MCP-Server als HTTP-Bridge deployen
git clone https://github.com/BayernTourismus/mcp-server
cd mcp-server && npm install
# Wrapper: stdio → SSE (z.B. via mcp-proxy oder eigener Express-Server)
BCT_API_TOKEN=xxx node src/bayerncloud.js
```

Danach ist der MCP Client Node konfigurierbar wie bei DZT. Alternativ: Die BayernCloud REST API direkt als natives Template implementieren (`data.bayerncloud.digital/api/v4/endpoints`).

#### Datenbank: `mcp_registry`

```sql
CREATE TABLE mcp_registry (
  id              SERIAL PRIMARY KEY,
  template_id     TEXT NOT NULL,
  template_type   TEXT NOT NULL DEFAULT 'native',  -- 'native' | 'bridge'
  n8n_workflow_id TEXT NOT NULL,
  name            TEXT,
  version         TEXT,
  active          BOOLEAN DEFAULT false,
  mcp_server_url  TEXT,                            -- nur für bridge-Typ
  credentials     JSONB DEFAULT '{}',
  installed_at    TIMESTAMPTZ DEFAULT NOW()
);
```

---

## 3. Phase 2: Credential Flow (One-Time-Link) (offen)

### 3.1 Warum kein direkter Schlüssel-Austausch im Chat

> 🔴 **Sicherheitsanalyse:** Telegram-Bot-Chats sind NICHT end-to-end-verschlüsselt. Telegram hält die Entschlüsselungsschlüssel. `deleteMessage()` löscht nicht zuverlässig von den Servern. Gleiches gilt für One.Intelligence: API-Keys im Chat-Verlauf sind dauerhaft gespeichert und potenziell einsehbar.

### 3.2 One-Time-Link-Flow

1. User: *"Ich möchte meinen Google Places API Key hinterlegen"*
2. Agent generiert UUID mit TTL (10 Min.) in PostgreSQL
3. Agent: *"Gib deinen Key sicher ein: https://n8n.example.com/form/add-key?token=abc123 (gültig 10 Min.)"*
4. User klickt Link, gibt Key in HTTPS-Formular (Password-Feld) ein
5. n8n speichert Credential via Credentials API, invalidiert Token
6. Agent: *"✅ Key sicher gespeichert. MCP-Server 'google-reviews' ist jetzt aktiv."*

### 3.3 Datenbank: `credential_tokens`

```sql
CREATE TABLE credential_tokens (
  token       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  template_id TEXT NOT NULL,
  cred_key    TEXT NOT NULL,
  cred_label  TEXT,
  user_email  TEXT,
  expires_at  TIMESTAMPTZ NOT NULL DEFAULT NOW() + INTERVAL '10 minutes',
  used        BOOLEAN DEFAULT false,
  created_at  TIMESTAMPTZ DEFAULT NOW()
);
```

### 3.4 Token generieren (Code Node)

```javascript
const templateId = $json.template_id;
const credKey = $json.cred_key;
const userEmail = $json.user_email;
const baseUrl = $env.N8N_BASE_URL;

const result = await $helpers.httpRequest({
  method: 'POST',
  url: `${$env.POSTGREST_URL}/credential_tokens`,
  headers: {
    'Authorization': `Bearer ${$env.POSTGREST_JWT}`,
    'Content-Type': 'application/json',
    'Prefer': 'return=representation'
  },
  body: JSON.stringify({ template_id: templateId, cred_key: credKey, user_email: userEmail })
});

const token = result[0].token;
const formUrl = `${baseUrl}/form/add-key?token=${token}`;

return [{ json: {
  message: `Bitte gib deinen ${credKey} sicher ein: ${formUrl} (gültig 10 Min.)`,
  token,
  form_url: formUrl
}}];
```

### 3.5 Credential empfangen und speichern

```javascript
// POST /webhook/add-key
const { token, api_key } = $json.body;

// Token validieren
const tokenRecord = await getTokenFromDB(token);
if (!tokenRecord || tokenRecord.used || new Date(tokenRecord.expires_at) < new Date()) {
  return [{ json: { error: 'Token ungültig oder abgelaufen' } }];
}

// Credential via n8n Credentials API speichern
await $helpers.httpRequest({
  method: 'POST',
  url: 'http://localhost:5678/api/v1/credentials',
  headers: { 'X-N8N-API-KEY': $env.N8N_API_KEY, 'Content-Type': 'application/json' },
  body: JSON.stringify({
    name: `${tokenRecord.cred_label} (${tokenRecord.user_email})`,
    type: 'httpHeaderAuth',
    data: { name: 'Authorization', value: `Bearer ${api_key}` }
  })
});

await markTokenUsed(token);
return [{ json: { success: true } }];
```

> **Hinweis:** Die n8n Credentials API hat keinen PUT-Endpunkt. Updates = DELETE + POST.

---

## 4. Phase 3: Tourismus-MCP-Server (offen)

> **Hinweis:** Das allgemeine Weather-Template (`weather-openmeteo`) ist bereits als Teil der Template Registry in Phase 1 umgesetzt. Die hier beschriebenen Tourismus-spezifischen MCP-Server sind noch offen.

### 4.1 weather-alpine (Open-Meteo) — teilweise umgesetzt als `weather-openmeteo`

| Parameter | Wert | Hinweis |
|-----------|------|---------|
| API | api.open-meteo.com | Kostenlos, kein Key |
| Geocoding | geocoding-api.open-meteo.com | Ortssuche nach Name |
| Limit (gratis) | 10.000 Calls/Tag | Nicht-kommerziell |
| Kommerziell | ab €29/Monat | Für Produktionseinsatz |
| Alpine Variablen | snow_depth, snowfall, freezing_level_height | |

```javascript
// Tool: get_snow_conditions(location: string)

const geoRes = await $helpers.httpRequest({
  url: `https://geocoding-api.open-meteo.com/v1/search?name=${encodeURIComponent(location)}&count=1&language=de`
});
const { latitude, longitude, name } = geoRes.results[0];

const weatherRes = await $helpers.httpRequest({
  url: 'https://api.open-meteo.com/v1/forecast',
  qs: {
    latitude, longitude,
    daily: 'snowfall_sum,snow_depth_max,temperature_2m_max,temperature_2m_min',
    hourly: 'freezing_level_height,snowfall',
    forecast_days: 7,
    timezone: 'Europe/Berlin'
  }
});

const currentHour = new Date().getHours();
return [{ json: {
  location: name, latitude, longitude,
  snow_depth_cm: Math.round(weatherRes.hourly.snowfall[currentHour] * 100),
  freezing_level_m: Math.round(weatherRes.hourly.freezing_level_height[currentHour]),
  forecast: weatherRes.daily
}}];
```

### 4.2 google-reviews

> ⚠️ **API-Limitierungen:** Max. 5 Reviews pro Abfrage, keine Pagination, keine Datumssortierung. Kosten: ~$25 pro 1.000 Requests.  
> **Lösung:** Nächtlicher Batch-Job speichert Reviews lokal in PostgreSQL. Agent liest aus lokaler DB.

#### Datenbankschema: `reviews`

```sql
CREATE TABLE reviews (
  id                SERIAL PRIMARY KEY,
  business_id       INTEGER REFERENCES member_businesses(id),
  google_review_id  TEXT UNIQUE,
  author            TEXT,
  rating            INTEGER,
  text              TEXT,
  published_at      TIMESTAMPTZ,
  answered          BOOLEAN DEFAULT false,
  fetched_at        TIMESTAMPTZ DEFAULT NOW()
);
```

#### Batch-Workflow (Cron: `0 3 * * *`)

```javascript
const businesses = await getActiveMembersWithPlaceId();

for (const business of businesses) {
  const reviews = await fetchGoogleReviews(business.google_place_id);
  const newReviews = reviews.filter(r => !existsInDB(r.review_id));
  await saveReviewsBatch(newReviews, business.id);
  await sleep(200); // Rate-Limit-Buffer
}
```

### 4.3 instagram-post

**Voraussetzungen:**
1. Instagram Business- oder Creator-Account
2. Facebook Page, mit Instagram-Account verknüpft
3. Meta Developer App erstellt, App Review abgeschlossen
4. Long-Lived Token generiert (gültig 60 Tage — Token-Rotation einrichten!)

#### Posting-Flow

```javascript
// Schritt 1: Container erstellen
const containerRes = await $helpers.httpRequest({
  method: 'POST',
  url: `https://graph.facebook.com/v19.0/${igUserId}/media`,
  body: {
    image_url: imageUrl,        // öffentlich erreichbare HTTPS-URL, nur JPEG
    caption: captionText,
    access_token: longLivedToken
  }
});

// Schritt 2: 10 Sekunden warten (Pflicht!) + veröffentlichen
await sleep(10000);

const publishRes = await $helpers.httpRequest({
  method: 'POST',
  url: `https://graph.facebook.com/v19.0/${igUserId}/media_publish`,
  body: { creation_id: containerRes.id, access_token: longLivedToken }
});

return [{ json: { post_id: publishRes.id, status: 'published' } }];
```

> ⚠️ Limit: 25 Posts/24h · Nur JPEG · Bilder müssen über HTTPS erreichbar sein · Token läuft nach 60 Tagen ab

#### Token-Rotation (Cron täglich)

```javascript
// Token-Ablauf prüfen:
// GET https://graph.facebook.com/debug_token?input_token={token}&access_token={app_id}|{app_secret}
// Wenn expires_in < 604800 (7 Tage): erneuern via fb_exchange_token Flow
```

### 4.4 scheduled-posts

```sql
CREATE TABLE scheduled_posts (
  id            SERIAL PRIMARY KEY,
  platform      TEXT NOT NULL,           -- 'instagram' | 'linkedin'
  caption       TEXT NOT NULL,
  image_url     TEXT,
  scheduled_at  TIMESTAMPTZ NOT NULL,
  status        TEXT DEFAULT 'pending',  -- 'pending' | 'published' | 'failed'
  created_by    TEXT,
  created_at    TIMESTAMPTZ DEFAULT NOW()
);

-- Cron jede Minute: SELECT * FROM scheduled_posts
-- WHERE status = 'pending' AND scheduled_at <= NOW()
-- → instagram-post MCP aufrufen, status auf 'published' setzen
```

---

## 5. Phase 4: DMO-Datenbank & Multi-User-Setup

### 5.1 Vollständiges Datenbankschema

```sql
-- Nutzer mit Rollen
CREATE TABLE users (
  telegram_id   BIGINT PRIMARY KEY,
  oi_email      TEXT UNIQUE,
  name          TEXT NOT NULL,
  role          TEXT NOT NULL,  -- 'marketing' | 'member_relations' | 'admin'
  active        BOOLEAN DEFAULT true,
  created_at    TIMESTAMPTZ DEFAULT NOW()
);

-- Mitgliedsbetriebe
CREATE TABLE member_businesses (
  id              SERIAL PRIMARY KEY,
  name            TEXT NOT NULL,
  category        TEXT,   -- 'hotel' | 'restaurant' | 'skiverleih' | 'bergbahn'
  google_place_id TEXT,
  email           TEXT,
  phone           TEXT,
  address         TEXT,
  active          BOOLEAN DEFAULT true
);

-- Aufgaben / offene Tasks
CREATE TABLE tasks (
  id          SERIAL PRIMARY KEY,
  user_id     BIGINT REFERENCES users(telegram_id),
  description TEXT NOT NULL,
  due_date    DATE,
  status      TEXT DEFAULT 'open',  -- 'open' | 'done'
  created_at  TIMESTAMPTZ DEFAULT NOW()
);
```

### 5.2 User-Routing im Agent-Workflow

```javascript
// Code Node: vor dem AI-Agent-Node
const userEmail = $json.body.user?.email || $json.body.user?.name;
const user = await getUserByEmail(userEmail);

const roleContext = {
  marketing: 'Du sprichst mit Sandra (Marketing). Tools: Wetter, Bewertungen, Instagram-Posting, Wochenbericht, Aufgaben.',
  member_relations: 'Du sprichst mit Thomas (Mitgliederbetreuung). Tools: Bewertungsabfrage, Mitglieder-Benachrichtigung, Antwort-Entwürfe.',
  admin: 'Admin-Modus. Alle Tools verfügbar.'
};

return [{ json: {
  chatInput: $json.body.chatInput,
  sessionId: $json.body.sessionId,
  userEmail,
  userName: user?.name || 'Unbekannt',
  role: user?.role || 'readonly',
  roleContext: roleContext[user?.role] || 'Eingeschränkter Zugriff.',
}}];
```

### 5.3 soul-Tabelle: Organisationsgedächtnis

```sql
INSERT INTO soul (key, value) VALUES
  ('organization_name', 'Tourismusverband Zugspitzregion e.V.'),
  ('region', 'Zugspitzregion, Bayern — Garmisch-Partenkirchen, Grainau, Mittenwald'),
  ('target_audience', 'Wintersportler, Wanderer, Familien, DACH-Markt'),
  ('tone_of_voice', 'Freundlich, professionell, regional verwurzelt. Wir duzen Gäste, siezen Pressevertreter.'),
  ('brand_hashtags', '#Zugspitze #ZugspitzRegion #Bayern #Wintersport #Wandern'),
  ('instagram_account', '@zugspitzregion_official'),
  ('member_count', '140'),
  ('current_season', 'Winter 2025/26'),
  ('key_resorts', 'Garmisch Classic, Zugspitze, Alpspix'),
  ('language', 'Deutsch'),
  ('pr_contact', 'presse@zugspitz-tourismus.de');
```

---

## 6. Phase 5: One.Intelligence Integration

### 6.1 Pipe Function (bei destination.one als Admin installieren)

```python
"""
title: n8n-claw Tourismus-Agent
author: Friedemann Schuetz
version: 1.0.0
description: Verbindet One.Intelligence mit n8n-claw für Tourism-DMOs
"""
from pydantic import BaseModel, Field
import requests
import time

class Pipe:
    class Valves(BaseModel):
        n8n_webhook_url: str = Field(
            default='https://n8n.friedemann-schuetz.de/webhook/dmo-agent',
            description='n8n Webhook URL des DMO-Agenten'
        )
        n8n_bearer_token: str = Field(default='', description='Bearer Token')
        input_field: str = Field(default='chatInput')
        response_field: str = Field(default='output')
        timeout: int = Field(default=120)

    def __init__(self):
        self.valves = self.Valves()

    def pipe(self, body: dict, __user__: dict = None) -> str:
        messages = body.get('messages', [])
        last_user_msg = next(
            (m['content'] for m in reversed(messages) if m['role'] == 'user'), ''
        )

        session_id = f"{__user__.get('email', 'anon')}-{int(time.time() // 3600)}"

        payload = {
            self.valves.input_field: last_user_msg,
            'sessionId': session_id,
            'user': {
                'email': __user__.get('email', ''),
                'name': __user__.get('name', ''),
                'role': __user__.get('role', 'user')
            },
            'messages': messages
        }

        headers = {'Content-Type': 'application/json'}
        if self.valves.n8n_bearer_token:
            headers['Authorization'] = f'Bearer {self.valves.n8n_bearer_token}'

        response = requests.post(
            self.valves.n8n_webhook_url,
            json=payload,
            headers=headers,
            timeout=self.valves.timeout
        )
        response.raise_for_status()
        return response.json().get(self.valves.response_field, '')
```

### 6.2 Modell-Konfiguration in One.Intelligence

| Feld | Wert |
|------|------|
| Name | DMO-Operationsassistent Zugspitzregion |
| Basis-Modell | n8n-claw Pipe Function |
| Sichtbarkeit | Nur Sandra + Thomas |
| System-Prompt | (leer — liegt in soul-Tabelle) |

**Starter Chips:** Morgen-Briefing · Neue Bewertungen · Instagram-Post erstellen · Mitglieder mit schlechten Bewertungen · Wochenbericht

### 6.3 Webhook-Payload (eingehend von Pipe Function)

```json
{
  "chatInput": "Zeig mir alle Betriebe mit unter 4 Sterne",
  "sessionId": "s.mueller@zugspitz-dmo.de-1741352400",
  "user": {
    "email": "s.mueller@zugspitz-dmo.de",
    "name": "Sandra Müller",
    "role": "user"
  },
  "messages": [...]
}
```

Antwort via **Respond to Webhook Node:**

```json
{ "output": "Hier sind die 3 Betriebe mit Bewertungen unter 4 Sterne..." }
```

---

## 7. Phase 6: Proaktives Briefing & Scheduling

### 7.1 Morgen-Briefing (Cron: `30 7 * * *`)

```javascript
const arrivals = await getArrivalsToday();
const newReviews = await getNewReviewsSince(yesterday);
const badReviews = newReviews.filter(r => r.rating <= 3);
const destinations = await getSoulValue('key_resorts');
const weather = await getWeatherForDestinations(destinations);
const tasks = await getTasksDueToday();

const briefingText = await callClaudeAPI(
  buildBriefingPrompt({ arrivals, newReviews, badReviews, weather, tasks })
);

await sendToAllActiveUsers(briefingText);
```

### 7.2 Proaktive Bewertungs-Benachrichtigung

```javascript
// Im Batch-Workflow, nach dem Review-Import:
const criticalReviews = newReviews.filter(r => r.rating <= 3);
if (criticalReviews.length > 0) {
  const message = criticalReviews.map(r =>
    `⚠️ ${r.business_name}: ${r.rating}★ — "${r.text.slice(0, 80)}..."`
  ).join('\n');

  await sendToUser('thomas',
    `Neue kritische Bewertungen:\n${message}\n\nSoll ich Benachrichtigungs-Mails senden?`
  );
}
```

### 7.3 Wochenbericht (Cron: `0 16 * * 5`)

```javascript
const weekData = {
  reviews: await getReviewsInRange(weekStart, now),
  avgRating: await calcAvgRatingThisWeek(),
  postsPublished: await getPublishedPostsCount(weekStart, now),
  tasksCompleted: await getCompletedTasksCount(weekStart, now),
  weatherHighlight: await getBestWeatherDay(weekStart, now)
};

const report = await callClaudeAPI(
  `Wochenbericht für Tourismusverband. Daten: ${JSON.stringify(weekData)}.
  Stil: Professionell, 1 Seite, mit Highlights und Handlungsempfehlungen.`
);

await sendToAllActiveUsers(report);
```

---

## 8. DMO Use Case: Dialogbeispiele

### 8.1 Sandra — Morgen-Briefing & Content

```
Sandra:   [Starter Chip] Morgen-Briefing

Agent:    Guten Morgen Sandra! Briefing für Montag, 10. März:

          📊 ANKÜNFTE HEUTE: 23 Gruppen (4 Neukunden)
          ⭐ NEUE BEWERTUNGEN (seit Fr.): 8 Bewertungen, Ø 4,2★
             ⚠️ Berggasthof Alpenblick: 2★ — "Wartezeit über 45 Min."
          🌨 WETTER ZUGSPITZE: ☀️ -3°C, Schneehöhe 180cm, Sicht sehr gut
          📋 OFFENE AUFGABEN: BR24-Anfrage (Frühlingsöffnungen) bis Mi

Sandra:   Schreib einen Instagram-Post zu den Schneeverhältnissen

Agent:    ❄️ 180 cm Schnee, Sonnenschein und −3°C auf der Zugspitze —
          der Winter zeigt nochmal alles, was er hat! 🏔️
          Wann kommst du? 👇
          #Zugspitze #ZugspitzRegion #Bayern #Wintersport

          Soll ich den Post für heute 17 Uhr einplanen?

Sandra:   Ja. Und erstell eine sachlichere LinkedIn-Version.

Agent:    ✅ Instagram: eingeplant für 17:00 Uhr.

          LinkedIn: "Die Zugspitzregion meldet optimale Wintersport-
          bedingungen: 180 cm Schneehöhe, stabile Temperaturen,
          sehr gute Sichtbedingungen. #Zugspitzregion #Wintertourismus"

          Einplanen oder als Entwurf speichern?
```

### 8.2 Thomas — Mitgliederbetreuung

```
Thomas:   Welche Betriebe haben diese Woche schlechte Bewertungen bekommen?

Agent:    3 Mitgliedsbetriebe mit ≤ 3★ diese Woche:

          1. Berggasthof Alpenblick — 2★ (Mo.) — "Wartezeit >45 Min."
          2. Ski & Bike Rental Zugspitz — 3★ (Sa.) — "Ausrüstung veraltet"
          3. Aparthotel Gipfelblick — 2★ (Fr.) — "Zimmer nicht gereinigt"

          Soll ich Benachrichtigungs-Mails an alle drei senden?

Thomas:   Ja, und für Berggasthof Alpenblick auch einen Antwort-Entwurf.

Agent:    ✅ 3 Mails versendet.

          Antwort-Entwurf Google (Berggasthof Alpenblick):
          "Lieber Gast, vielen Dank für Ihr ehrliches Feedback.
          Es tut uns leid, dass Sie längere Wartezeiten erlebt haben.
          Wir haben das Thema im Team besprochen. Wir freuen uns,
          Sie bald wieder begrüßen zu dürfen."

          Direkt an Betriebsleitung weiterleiten?
```

---

## 9. Alleinstellungsmerkmal vs. Standard-Webhook-Agent

| Funktion | Standard Webhook-Agent | n8n-claw |
|----------|----------------------|----------|
| Gedächtnis | Vergisst nach Chat | PostgreSQL — dauerhaft |
| Organisation kennen | Nur System-Prompt | soul-Tabelle — lebendig |
| Neue Integrationen | Manueller Workflow-Bau | MCP Builder per Chat |
| Proaktiv | Wartet auf Anfragen | Briefings, Alerts, Cron |
| Multi-User | Komplexe Anpassung | users-Tabelle + Routing |
| Reproduzierbar | Handarbeit pro DMO | Template Pack — skaliert |

> **Das Alleinstellungsmerkmal in einem Satz:**  
> **Memory + Self-Extension + Organisationskontext + Proaktivität** = ein Agent, der mit der Organisation mitwächst, sich selbst erweitert und den Nutzern begegnet, bevor sie fragen.  
> Kein anderes Modell im One.Intelligence Marketplace kann das.

**Wirtschaftlichkeit:**
- Erste Einrichtung (DMO 1): ca. 15–20 Stunden Beratungszeit
- Folge-DMOs: ca. 8–12 Stunden (Template Pack)
- Monatliche Wartung: ca. 2–4 Stunden

**Positionierung:** Das Setup liefert direkt Level 5 des Destination.One-Fünf-Stufen-Plans (action model) — als Consulting-Paket, nicht als Eigenentwicklung.

---

## 10. Implementierungsreihenfolge für Claude Code

### Phase 1 — ✅ Done (v0.6.0)

1. ✅ GitHub-Repo `n8n-claw-templates` anlegen + `index.json` + 7 Templates
2. ✅ jsDelivr-Integration: CDN abrufbar (mit Commit-Hash für Cache-Kontrolle)
3. ⏭️ GitHub Action für CDN-Cache-Purge — übersprungen (Commit-Hash reicht)
4. ✅ Library Manager Workflow: `list_templates`, `install_template`, `remove_template`

### Phase 2 — Offen

5. `credential_tokens` Tabelle + Formular-Webhook implementieren

### Phase 3-6 — Offen (Tourismus-spezifisch)

6. Tourismus-MCP-Server (google-reviews, instagram-post, etc.)
7. Datenbankschema: `users`, `member_businesses`, `reviews`, `tasks`, `scheduled_posts`
8. User-Routing + Multi-User-Setup
9. Bridge-Templates (dzt-knowledge-graph, bayerncloud-events)
10. One.Intelligence Pipe Function
11. Proaktive Briefings + Wochenbericht

> 💡 **Claude Code Hinweis:** Jeder Schritt ist ein eigenständiger, testbarer Meilenstein.

---

*n8n-claw Tourismus-Plattform · Friedemann Schuetz / n8n Ambassador Rhein-Ruhr · März 2026*
