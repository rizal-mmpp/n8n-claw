# 🤖 n8n-claw — Self-Hosted AI Agent

A fully self-hosted AI agent built on n8n + PostgreSQL + Claude. Talks to you via Telegram, builds its own MCP tools, manages reminders and memory — all running on your own infrastructure.

## What it does

- **Telegram chat** — talk to your AI agent directly via Telegram
- **Long-term memory** — remembers conversations and important context in PostgreSQL with optional vector search (RAG)
- **MCP Server Builder** — builds new API integrations on demand (just ask: *"build me an MCP server for the GitHub API"*)
- **Smart reminders** — timed Telegram reminders
- **Extensible** — add new tools and capabilities through natural language

## Architecture

```
Telegram
  ↓
n8n-claw Agent (Claude Sonnet)
  ├── Memory Save/Search (PostgreSQL + vector embeddings)
  ├── Memory Consolidation (daily RAG pipeline)
  ├── MCP Client → MCP Servers (n8n workflows)
  ├── MCP Builder → creates new MCP Servers automatically
  └── Reminder Factory
```

---

## Installation

### What you need

- A Linux VPS (Ubuntu 22.04/24.04 recommended, 2GB RAM minimum)
- A **Telegram Bot** — create one via [@BotFather](https://t.me/BotFather)
- Your **Telegram Chat ID** — get it from [@userinfobot](https://t.me/userinfobot)
- An **Anthropic API Key** — from [console.anthropic.com](https://console.anthropic.com)
- A **domain name** (optional but recommended, required for Telegram HTTPS webhooks)

### Step 1 — Clone & run

```bash
git clone https://github.com/freddy-schuetz/n8n-claw.git && cd n8n-claw && ./setup.sh
```

The script will:

1. **Update the system** (`apt update && apt upgrade`)
2. **Install Docker** automatically if not present
3. **Start n8n** so you can generate an API key
4. **Ask you for configuration** interactively:
   - n8n API Key *(generated in n8n UI → Settings → API)*
   - Telegram Bot Token
   - Telegram Chat ID
   - Anthropic API Key
   - Domain name *(optional — enables HTTPS via Let's Encrypt + nginx)*
5. **Configure your agent's personality**:
   - Agent name
   - Your name
   - Preferred language
   - Timezone *(auto-detected from system)*
   - Communication style (casual / professional / friendly)
   - Proactive vs reactive behavior
   - Free-text custom persona *(overrides the above)*
6. **Start all services** (n8n, PostgreSQL, PostgREST, Kong)
7. **Apply database schema** and seed data
8. **Create n8n credentials** (Telegram Bot automatically)
9. **Import all workflows** into n8n
10. **Wire workflow references** (MCP Builder, Reminders, etc.)
11. **Activate the agent** automatically

### Step 2 — Add credentials in n8n UI

Open n8n at the URL shown at the end of setup.

The easiest way is to open each workflow and click **"Create new credential"** directly on the node that needs it. n8n will prompt you automatically.

**Credentials you'll need:**

| Credential | Name (exact!) | Where needed |
|---|---|---|
| Postgres | `Supabase Postgres` | Agent (Load Soul, Load History, etc.) |
| Anthropic API | `Anthropic API` | Agent (Claude node), MCP Builder |
| Telegram Bot | `Telegram Bot` | Agent (Telegram Trigger + Reply) — *created automatically by setup* |

**Postgres connection details** *(shown in setup output)*:
- Host: `db` | Port: `5432` | DB: `postgres` | User: `postgres`
- Password: *(shown at end of setup)*
- SSL: `disable`

**MCP Builder — select LLM model:**
- Open the MCP Builder workflow → click the LLM node
- Select `Anthropic API` as the chat model
- *(not set automatically due to n8n credential linking)*

**MCP Builder — Brave Search API Key:**
- The MCP Builder uses Brave Search to look up API documentation automatically
- Open the **MCP Builder** workflow → click the **"Search API Docs"** node
- Under *Headers*, set `X-Subscription-Token` to your Brave Search API key
- Get a free key at [brave.com/search/api](https://brave.com/search/api/) (free tier: 2,000 queries/month)
- Without this key, the MCP Builder cannot find API docs automatically — you'd need to paste docs manually into the prompt

**Optional: Embeddings for semantic memory search:**

During setup, you'll be asked for an embedding API key. This enables vector-based memory search (RAG) — the agent can find memories by meaning, not just exact keywords.

- **OpenAI** (default): `text-embedding-3-small` — [platform.openai.com](https://platform.openai.com) (requires API key)
- **Voyage AI**: `voyage-3-lite` — [voyageai.com](https://www.voyageai.com) (free tier available)
- **Ollama**: `nomic-embed-text` — local, no API key needed (requires Ollama running on your server)

Without an embedding key, the agent still works — it falls back to keyword-based memory search.

### Step 3 — Activate remaining workflows

The main agent is activated automatically by setup. In n8n UI, toggle the remaining workflows on:

| Workflow | Purpose |
|---|---|
| 🤖 n8n-claw Agent | Main agent *(activated by setup)* |
| 🏗️ MCP Builder | Builds new MCP Server workflows on demand |
| 🔌 MCP Client | Calls tools on MCP Servers (sub-workflow) |
| ⏰ ReminderFactory | Creates timed Telegram reminders |
| 🌤️ MCP: Weather | Example MCP Server — weather via Open-Meteo (no API key) |
| ⚙️ WorkflowBuilder | Builds general n8n automations |
| 🧠 Memory Consolidation | Daily RAG pipeline — summarizes conversations into vector memory |

### Step 4 — Start chatting

Send a message to your Telegram bot. It's ready!

---

## Services & URLs

After setup, these services run:

| Service | URL | Purpose |
|---|---|---|
| n8n | `http://YOUR-IP:5678` | Workflow editor |
| Supabase Studio | `http://localhost:3001` (via SSH tunnel) | Database admin UI |
| PostgREST API | `http://YOUR-IP:8000` | REST API for PostgreSQL |

### Accessing Supabase Studio

Supabase Studio is bound to `localhost` only (not publicly exposed). To access it from your browser, open an SSH tunnel:

```bash
ssh -L 3001:localhost:3001 user@YOUR-VPS-IP
```

Then open `http://localhost:3001` in your browser. The tunnel stays open as long as the SSH session runs.

---

## Building new MCP tools

Just ask your agent:
> "Build me an MCP server for the OpenLibrary API — look up books by ISBN"

The MCP Builder will:
1. Search for API documentation automatically (via Brave Search + Jina Reader)
2. Generate working tool code
3. Deploy two new n8n workflows (MCP trigger + sub-workflow)
4. Register the server in the database
5. Update the agent so it knows about the new tool

> ⚠️ After each MCP build: **deactivate → reactivate** the new MCP workflow in n8n UI (required due to a webhook registration bug in n8n).

---

## Customization

Edit the `soul` and `agents` tables directly in Supabase Studio (`http://localhost:3001` via [SSH tunnel](#accessing-supabase-studio)) to change your agent's personality, tools, and behavior — no code changes needed.

| Table | Contents |
|---|---|
| `soul` | Agent personality (name, persona, vibe, language, boundaries) |
| `agents` | Tool instructions, MCP config, memory behavior, user context |
| `user_profiles` | User name, timezone, context |
| `mcp_registry` | Available MCP servers |
| `conversations` | Chat history |
| `memory_long` | Long-term memory with semantic search |

---

## HTTPS Setup

If you provided a domain during setup, HTTPS is configured automatically via Let's Encrypt. If not, you can add it later:

```bash
DOMAIN=n8n.yourdomain.com ./setup.sh
```

Point your domain's DNS A record to the VPS IP before running this.

> ⚠️ **Security note:** Without a domain, n8n runs over plain HTTP with no TLS and no rate limiting. This is fine for **local installs** (home server, LAN, testing). For a **public VPS**, always use a domain with HTTPS — otherwise credentials are transmitted unencrypted and the instance is exposed to the internet.

---

## Updating

Re-run `setup.sh` at any time to update:

```bash
cd n8n-claw && ./setup.sh
```

In update mode, the script will:
- **Auto-update from git** (`git pull --ff-only`) — falls back gracefully if there are local changes
- **Pull latest Docker images** (n8n, PostgreSQL, etc.)
- **Restart all services** with the new images
- **Preserve your encryption key** — automatically recovered from the existing volume
- **Skip personalization** — your agent's name, personality, and timezone are kept
- **Skip credential creation and workflow import** — nothing is duplicated

To **reconfigure** your agent's personality, timezone, or other settings:

```bash
./setup.sh --force
```

This re-runs the full setup wizard while keeping your existing data and credentials.

---

## Troubleshooting

**Agent not responding to Telegram messages?**
→ Check all workflows are **activated** in n8n UI

**"Credential does not exist" error?**
→ Add the Postgres credential manually (see Step 2)

**MCP Builder fails?**
→ Make sure the LLM node in MCP Builder has Anthropic API selected

**Agent shows wrong time?**
→ Re-run `./setup.sh --force` and set the correct timezone, or update it directly in `user_profiles` table via Supabase Studio

**DB empty / Load Soul returns nothing?**
→ Re-run seed: `./setup.sh` (skips already-set config)

**Logs:**
```bash
docker logs n8n-claw        # n8n
docker logs n8n-claw-db     # PostgreSQL
docker logs n8n-claw-rest   # PostgREST
```

---

## Optional: WorkflowBuilder with Claude Code

The WorkflowBuilder tool lets your agent build complex n8n workflows using Claude Code CLI. This requires additional setup:

### 1. Install the community node

In n8n UI → Settings → Community Nodes → Install:
```
n8n-nodes-claude-code-cli
```

### 2. Install Claude Code on your VPS

```bash
# Install Node.js if needed
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt-get install -y nodejs

# Install Claude Code CLI globally
npm install -g @anthropic-ai/claude-code

# Verify
claude --version
```

### 3. Configure in n8n

- Open the WorkflowBuilder workflow
- The Claude Code node needs access to the CLI
- Set `ANTHROPIC_API_KEY` environment variable in your n8n container:

```yaml
# Add to docker-compose.yml under n8n environment:
- ANTHROPIC_API_KEY=your_key_here
```

Then restart: `docker compose up -d n8n`

> Without this setup, the WorkflowBuilder tool won't function — but all other agent capabilities work fine without it.

---

## Stack

- **[n8n](https://n8n.io)** — workflow automation engine
- **PostgreSQL** — database
- **[PostgREST](https://postgrest.org)** — auto-generated REST API
- **[Kong](https://konghq.com)** — API gateway
- **[Claude](https://anthropic.com)** (Anthropic) — LLM powering the agent
- **Telegram** — messaging interface
- **[Open-Meteo](https://open-meteo.com)** — free weather API (example MCP, no key needed)

---

## License

MIT
