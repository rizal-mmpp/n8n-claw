# Local Setup Guide (Docker + ngrok)

This guide explains how to run n8n-claw locally on your machine using Docker and ngrok — no VPS required. Ideal for testing and development.

Tested on: **Debian 13 (KDE)** with Docker and ngrok already installed.

> **Scope of this guide:** This setup was tested for core agent functionality — Telegram chat, task management, web search, web reader, reminders, and basic memory. Some advanced features (MCP Builder, WorkflowBuilder, Agent Library, semantic memory search, voice/photo support) require additional configuration documented below but were not fully tested in the local environment. See the notes in each relevant section.

---

## Prerequisites

- [Docker](https://docs.docker.com/engine/install/debian/) installed and running
- [ngrok](https://ngrok.com/) installed and authenticated — follow the [official quickstart guide](https://ngrok.com/docs/getting-started/) for your OS
- A Telegram bot token — create one via [@BotFather](https://t.me/BotFather)
- Your Telegram Chat ID — get it from [@userinfobot](https://t.me/userinfobot)
- An Anthropic API key — from [console.anthropic.com](https://console.anthropic.com) (pay-as-you-go, no subscription needed — $5 credit is enough for months of testing)

> **Note:** The official `setup.sh` script (located in the repo root) is designed for a fresh Linux VPS running as root. It automates everything: system updates, Docker install, credential creation, workflow import, placeholder substitution, workflow wiring, and agent activation. For local Docker setups, follow this guide instead — it replaces the automated script with manual steps that work on any machine.

---

## Step 1 — Clone the repo

Open a terminal and navigate to the folder where you want to install n8n-claw. The clone command will create a new `n8n-claw` subfolder in whatever directory you are currently in.

For example, to install on your Desktop:

```bash
cd ~/Desktop
git clone https://github.com/freddy-schuetz/n8n-claw.git
cd n8n-claw
```

Or in your Home directory:

```bash
cd ~
git clone https://github.com/freddy-schuetz/n8n-claw.git
cd n8n-claw
```

> Everything — Docker configuration, workflow files, database migrations — lives inside the `n8n-claw` folder. When you're done testing, deleting this folder (along with Docker volumes) removes everything cleanly. All subsequent commands in this guide must be run from inside this folder.

---

## Step 2 — Replace placeholders

The workflow JSON files and the SearXNG config contain placeholder strings that `setup.sh` normally replaces automatically. In a local setup, you must do this **before importing anything into n8n**.

### 2a — Start ngrok first

You need your public URL before running the substitution:

```bash
ngrok http 5678
```

Copy the `https://` URL shown (e.g. `https://abc123.ngrok-free.app`). Keep this terminal open — **the ngrok tunnel must stay open for the entire session**. If ngrok stops, Telegram webhooks stop working and the agent won't respond.

### 2b — Extract the credential-form webhook ID

`setup.sh` extracts this value from `credential-form.json` before import. Do the same locally:

```bash
python3 -c "
import json
wf = json.load(open('workflows/credential-form.json'))
for n in wf.get('nodes', []):
    if n.get('webhookId'):
        print(n['webhookId'])
        break
"
```

Copy the output — you'll need it in the next command.

### 2c — Patch workflow files

Run this command replacing the placeholder values with your own:

```bash
find workflows/ -name "*.json" -exec sed -i \
  's|{{SUPABASE_URL}}|http://kong:8000|g;
   s|{{SUPABASE_SERVICE_KEY}}|eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyb2xlIjoic2VydmljZV9yb2xlIn0.M2d2z4SFn5C7HlJlaSLfrzuZim_14wxiQEyFBMeOkSQ|g;
   s|{{SUPABASE_ANON_KEY}}|eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyb2xlIjoiYW5vbiJ9.ZopqoUt20nEV8rw6HtnRmNIyOFZE1dIknwpBI9gn06w|g;
   s|{{N8N_URL}}|https://YOUR-NGROK-URL|g;
   s|{{N8N_INTERNAL_URL}}|http://172.17.0.1:5678|g;
   s|{{N8N_API_KEY}}|YOUR-N8N-API-KEY|g;
   s|{{TELEGRAM_CHAT_ID}}|YOUR-TELEGRAM-CHAT-ID|g;
   s|{{CREDENTIAL_FORM_WEBHOOK_ID}}|YOUR-CREDENTIAL-FORM-WEBHOOK-ID|g' {} \;
```

Replace:
- `https://YOUR-NGROK-URL` → your ngrok URL
- `YOUR-N8N-API-KEY` → generate this in Step 6, then **re-run this command** with the real value
- `YOUR-TELEGRAM-CHAT-ID` → your Telegram Chat ID
- `YOUR-CREDENTIAL-FORM-WEBHOOK-ID` → the value from Step 2b

> This patches all workflow JSON files in one pass. Without this step, all tools that interact with the database (Memory Save, Memory Search, Task Manager, Reminder, etc.) will silently fail with an unknown error when triggered. The internal database URL is `http://kong:8000` — not `http://localhost:8000` — because inside the Docker network, containers reach each other by service name as defined in `docker-compose.yml`.

### 2d — Patch SearXNG config

`setup.sh` also generates a secret key for SearXNG. Do the same locally:

```bash
SEARXNG_SECRET=$(openssl rand -hex 32)
sed -i "s|{{SEARXNG_SECRET_KEY}}|${SEARXNG_SECRET}|g" searxng/settings.yml
```

> Without this, SearXNG may fail to start or refuse requests. Web search will not work.

---

## Step 3 — Generate kong.deployed.yml

Kong is the API gateway that sits in front of PostgREST and controls authenticated access to the database. Generate its config manually:

```bash
sed 's/{{SUPABASE_ANON_KEY}}/eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyb2xlIjoiYW5vbiJ9.ZopqoUt20nEV8rw6HtnRmNIyOFZE1dIknwpBI9gn06w/g; s/{{SUPABASE_SERVICE_KEY}}/eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyb2xlIjoic2VydmljZV9yb2xlIn0.M2d2z4SFn5C7HlJlaSLfrzuZim_14wxiQEyFBMeOkSQ/g' supabase/kong.yml > supabase/kong.deployed.yml
```

> Without `kong.deployed.yml`, the Kong container fails to start and no workflow can reach the database.
>
> The keys used here are the standard Supabase self-hosted **development keys**, publicly documented by Supabase as safe defaults for local and non-production environments. Source: [supabase.com/docs/guides/self-hosting/docker#generate-api-keys](https://supabase.com/docs/guides/self-hosting/docker#generate-api-keys). Do not use them in production.

---

## Step 4 — Create the .env file

```bash
cp .env.example .env
```

Open `.env` and fill in the minimum required values. Add `N8N_API_KEY` as an empty line — you will fill it in Step 6 after generating it from the n8n UI:

```env
# n8n — update with your ngrok URL from Step 2
N8N_URL=https://YOUR-NGROK-URL
N8N_INTERNAL_URL=http://172.17.0.1:5678
N8N_HOST=localhost
N8N_PROTOCOL=http
N8N_WEBHOOK_URL=https://YOUR-NGROK-URL
N8N_API_KEY=

# Generate any random string for these two
N8N_ENCRYPTION_KEY=localtest123xyz456abc
POSTGRES_PASSWORD=localtest123

# Supabase — use the same keys from Step 3
SUPABASE_URL=http://localhost:8000
SUPABASE_JWT_SECRET=super-secret-jwt-token-for-local-testing
SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyb2xlIjoiYW5vbiJ9.ZopqoUt20nEV8rw6HtnRmNIyOFZE1dIknwpBI9gn06w
SUPABASE_SERVICE_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyb2xlIjoic2VydmljZV9yb2xlIn0.M2d2z4SFn5C7HlJlaSLfrzuZim_14wxiQEyFBMeOkSQ

# Telegram
TELEGRAM_BOT_TOKEN=your_bot_token
TELEGRAM_CHAT_ID=your_chat_id

# Anthropic
ANTHROPIC_API_KEY=your_anthropic_key

# Timezone
TIMEZONE=Europe/Rome
```

> `N8N_ENCRYPTION_KEY` encrypts stored credentials — never change it after first run or all saved credentials become unreadable. `setup.sh` generates it with `openssl rand -hex 16`; a fixed string works fine for local testing.

### Optional services

The following were not tested in this local setup. The core agent works fully without them.

| Variable | Feature | Status in local test | How to enable |
|---|---|---|---|
| `EMBEDDING_API_KEY` | Semantic memory search (RAG) — finds memories by meaning. Without it, memory works with keyword search only. | ⚠️ Not tested | [OpenAI](https://platform.openai.com), [Voyage AI](https://voyageai.com) (free tier), or [Ollama](https://ollama.com) locally. Set `EMBEDDING_PROVIDER` accordingly. |
| OpenAI API key | Voice transcription (Whisper) + photo analysis (GPT-4o Vision) | ⚠️ Not tested | Add real OpenAI key to `OpenAI API` credential in n8n |
| `BRAVE_API_KEY` | Alternative web search for MCP Builder | ⚠️ Not tested | Free at [brave.com/search/api](https://brave.com/search/api) — 2,000 req/month |
| `NEXTCLOUD_URL/USER/PASS` | CalDAV calendar integration | ⚠️ Not tested | Requires a running Nextcloud instance |
| `VEXA_API_KEY` | Meeting intelligence | ⚠️ Not tested | Requires a running [Vexa](https://github.com/vexa) instance |

---

## Step 5 — Start the containers

```bash
docker compose up -d
```

> Use `docker compose` without hyphen — Docker Compose v2 syntax. On first run, Docker downloads all required images — this may take a few minutes.

Verify everything is running:

```bash
docker compose ps
```

You should see all containers with status `Up` or `healthy`:
- `n8n-claw` — the n8n workflow engine
- `n8n-claw-db` — PostgreSQL database
- `n8n-claw-rest` — PostgREST, auto-generates a REST API from the database
- `n8n-claw-kong` — API gateway, handles authentication for database requests
- `n8n-claw-studio` — Supabase Studio, web UI for browsing the database
- `n8n-claw-meta` — Postgres Meta, used internally by Supabase Studio
- `n8n-claw-crawl4ai` — web crawler that returns clean markdown from any URL
- `n8n-claw-searxng` — self-hosted meta search engine, no API key needed
- `n8n-claw-email-bridge` — IMAP/SMTP bridge for email integration

> The database schema is applied automatically by the PostgreSQL container on first start, via the migration files in `supabase/migrations/`. This includes all tables (`soul`, `user_profiles`, `agents`, `tasks`, `reminders`, `memory_long`, `mcp_registry`, etc.) and seed data.

---

## Step 6 — Create your n8n account and API key

1. Open [http://localhost:5678](http://localhost:5678)
2. Create your admin account (save your password!)
3. Go to **Settings → n8n API → Create an API key**
4. Copy the key and add it to your `.env`:

```env
N8N_API_KEY=the_key_you_just_generated
```

Then restart n8n:

```bash
docker compose restart n8n
```

---

## Step 6b — Re-run placeholder substitution with the real API key

Now that you have the real `N8N_API_KEY`, you must re-run the substitution command from Step 2c with the actual value. This is required for the MCP Builder and Self Modify tools to work correctly.

```bash
find workflows/ -name "*.json" -exec sed -i \
  's|YOUR-N8N-API-KEY|the_key_you_just_generated|g' {} \;
```

Replace `the_key_you_just_generated` with your actual API key.

> `setup.sh` collects the API key interactively before doing any substitution, so it never has this two-pass problem. In the local setup, we must generate the key first and then patch the workflows — do not skip this step or MCP Builder and Self Modify will fail silently.

---

## Step 7 — Import the workflows

Import order matters — follow this exact sequence so that sub-workflows exist before the workflows that call them:

1. mcp-client
2. reminder-factory
3. reminder-runner
4. mcp-weather-example (🌤️ MCP: Weather)
5. workflow-builder
6. mcp-builder
7. mcp-library-manager
8. agent-library-manager
9. sub-agent-runner
10. credential-form
11. memory-consolidation
12. background-checker
13. heartbeat
14. **n8n-claw-agent (last)**

To import: click the **three dots menu (⋮) in the top right** of the n8n UI → **Import from file**, then select each `.json` file from the `workflows/` folder.

> The Agent workflow is imported last because all other workflow IDs must exist before wiring its internal references in Step 9.

---

## Step 8 — Add credentials

Create credentials directly from the nodes inside the workflows.

Open the **🤖 n8n-claw Agent** workflow and connect credentials by clicking on each node that requires them:

- **Anthropic node** → Anthropic API credential → enter your API key
- **Telegram Trigger node** → Telegram Bot credential → enter your bot token
- **Postgres nodes** → Postgres credential with:
  - Host: `db` — Port: `5432` — Database: `postgres` — User: `postgres`
  - Password: your `POSTGRES_PASSWORD` from `.env`
  - SSL: `disable`

Also open **🏗️ MCP Builder** and **🧠 Sub-Agent Runner** and connect the same Anthropic and Postgres credentials there.

> The host `db` refers to the PostgreSQL container by its Docker service name — not `localhost` — because inside the Docker network each container is reached by its service name as defined in `docker-compose.yml`.

> **Note on credentials in workflows:** When opening a workflow, you may see a warning that credentials are not set even though you already created them. This is a display glitch — simply open the affected node and close it again without making changes. n8n will refresh the credential state and the warning will disappear.

### MCP Builder — extra step

After connecting credentials in MCP Builder, open the workflow, click the **LLM node**, and select `Anthropic API` as the chat model. This is not linked automatically.

> ⚠️ **Not fully tested in local setup** — MCP Builder requires `N8N_API_KEY` and `N8N_INTERNAL_URL` to be correctly substituted (Step 2c) and needs to reach the n8n API from inside the Docker network.

### WorkflowBuilder — skip for now

WorkflowBuilder requires the community node `n8n-nodes-claude-code-cli` to be installed first (Settings → Community Nodes). Without it, the workflow cannot be published. This feature is optional and was not tested in the local setup — skip it for now.

### Handling OpenAI nodes

Create a placeholder OpenAI credential with a fake key (e.g. `sk-fake123`) — this allows workflows to publish without errors. Voice and photo nodes will fail if triggered, but the rest of the agent works normally. Replace with a real key when you want to enable those features.

---

## Step 9 — Fix workflow references

`setup.sh` replaces all `REPLACE_*_ID` placeholders programmatically. In local setup, do this manually by switching each reference from "By ID" to "From list".

### In 🤖 n8n-claw Agent

Open the **AI Agent** node and select the tools sub-nodes listed below. For each one, switch the workflow reference from "By ID" to "From list":

| Tool name in AI Agent node | Select from list |
|---|---|
| Reminder | `⏰ ReminderFactory` |
| WorkflowBuilder | `⚙️ WorkflowBuilder` |
| MCP Builder | `🏗️ MCP Builder` |
| Library Manager | `📚 MCP Library Manager` |
| Expert Agent | `🧠 Sub-Agent Runner` |
| Agent Library | `📖 Agent Library Manager` |

### In 💓 Heartbeat

| Node | Select from list |
|---|---|
| Execute Background Checker | `🔍 Background Checker` |
| Execute Agent | `🤖 n8n-claw Agent` |

### In ⏰ Reminder Runner

| Node | Select from list |
|---|---|
| Execute Agent | `🤖 n8n-claw Agent` |

---

## Step 10 — Fix webhook authentication

Some workflows have a **Webhook Trigger** node configured with **Header Auth** but no credential selected — this blocks publishing.

For each affected workflow:
1. Open the Webhook Trigger node
2. Change **Authentication** from `Header Auth` to `None`
3. Save

> This is safe for local testing — the webhook is not publicly exposed beyond your ngrok tunnel.

---

## Step 11 — Publish workflows

Publish in this order — dependencies first. **n8n-claw Agent must be published last.**

1. Sub-workflows first:
   - 🔌 MCP Client
   - ⏰ ReminderFactory
   - 🧠 Sub-Agent Runner
   - 📚 MCP Library Manager
   - 📖 Agent Library Manager
   - 🔐 credential-form
2. Then:
   - 🔍 Background Checker
   - 🌤️ MCP: Weather
   - 🏗️ MCP Builder
   - 🧠 Memory Consolidation
   - ⚙️ WorkflowBuilder *(skip if you haven't installed the community node `n8n-nodes-claude-code-cli` — not required for core functionality)*
3. Then publish the Agent:
   - 🤖 **n8n-claw Agent**
4. Finally, after the Agent is published:
   - ⏰ Reminder Runner
   - 💓 Heartbeat

> **Why this order?** Reminder Runner and Heartbeat reference the Agent workflow — they require it to be published and active before they can activate themselves. Publishing the Agent also automatically registers the **production webhook** with Telegram via the Telegram Bot API — no manual webhook registration needed. From this point, your Telegram bot is live and the agent will respond to messages.

> ⚙️ **WorkflowBuilder** requires the community node `n8n-nodes-claude-code-cli` (see Step 8). Skip it if you haven't installed the node.

---

## Step 12 — Test it

Send a message to your Telegram bot. The agent should respond.

### Tested and working in local setup ✅

```
"What can you do?"
"Create a task: test n8n-claw, high priority"
"Show my tasks"
"Search the web for latest n8n news"
"Read this page: https://n8n.io/blog"
"Remind me in 2 minutes to check this"
"What's the weather in Rome?"
"Remember that I prefer morning meetings"
"What do you remember about me?"
```

### Not tested in local setup ⚠️

- Voice message transcription (requires real OpenAI key)
- Photo analysis (requires real OpenAI key)
- Semantic memory search / RAG (requires embedding API key)
- MCP Builder — building custom skills (requires verified N8N_API_KEY substitution)
- WorkflowBuilder with Claude Code (requires community node install)
- Installing MCP skills that require API keys (requires credential-form webhook)
- Expert agents delegation (not verified end-to-end)

---

## Customizing your agent

### Via Telegram chat (easiest)

```
"From now on your name is Max"
"Always reply in Italian, casual and direct tone"
"You are a technical assistant specialized in web development"
"Be proactive and suggest things I might have forgotten"
```

The agent updates its own profile in the database automatically.

### Via Supabase Studio (full control)

Open [http://localhost:3001](http://localhost:3001) — the database UI. Edit these tables:

| Table | What to change |
|---|---|
| `soul` | Agent name, persona, tone, behavior boundaries |
| `user_profiles` | Your name, language, timezone, preferences |
| `agents` | Tool instructions, MCP config, memory behavior |

No restart needed — changes apply on the next conversation.

---

## Cleanup — remove everything

```bash
docker compose down -v   # stops containers and deletes volumes
cd ..
rm -rf n8n-claw          # removes the project folder
```

> The `-v` flag removes named Docker volumes (`n8n_data`, `db_data`). Without it, those volumes persist on disk even after the containers and project folder are gone.

---

## Troubleshooting

**Agent not responding on Telegram**
→ Check all workflows are published
→ Verify ngrok is still running and the URL in `.env` matches the current session

**Unknown error on Memory Save / Task Manager / Reminder or any DB tool**
→ Placeholders not substituted. Re-run Step 2c before importing, or fix manually: replace `{{SUPABASE_URL}}` with `http://kong:8000` and `{{SUPABASE_SERVICE_KEY}}` with the service key directly in the node's code editor.

**MCP Builder fails**
→ Verify `{{N8N_API_KEY}}` and `{{N8N_INTERNAL_URL}}` were correctly substituted in Step 2c. If you generated the API key after the first substitution pass, re-run with the real key.

**Credential form link doesn't work when installing MCP skills**
→ Verify `{{CREDENTIAL_FORM_WEBHOOK_ID}}` was substituted correctly in Step 2c using the value from Step 2b.

**"Credential does not exist" error or credential warning in workflow**
→ Open the affected node and close it without changes — n8n will refresh the credential state. If the error persists, connect the credential directly on that node.

**Workflow won't publish — webhook authentication error**
→ Open the Webhook Trigger node and change Authentication to `None` (see Step 10).

**WorkflowBuilder won't publish**
→ Install the community node `n8n-nodes-claude-code-cli` first (Settings → Community Nodes), or skip WorkflowBuilder — it is not required for core agent functionality.

**Workflow won't publish — node references not found**
→ Check for `REPLACE_*_ID` placeholders and switch them to "From list" (see Step 9).

**Reminder Runner or Heartbeat won't activate**
→ Make sure 🤖 n8n-claw Agent is published first — both workflows depend on it being active.

**ngrok URL changed after restart**
→ Update `N8N_URL` and `N8N_WEBHOOK_URL` in `.env`, re-run Step 2c with the new URL, re-import affected workflows, then `docker compose restart n8n`.

**Check logs**
```bash
docker logs n8n-claw         # n8n
docker logs n8n-claw-db      # PostgreSQL
docker logs n8n-claw-searxng # SearXNG
```

---

*Guide written and tested on Debian 13 / KDE. Core agent functionality verified. Advanced features (MCP Builder, voice/photo, RAG memory) require additional configuration — see notes above. Contributions welcome.*
