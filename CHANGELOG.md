# Changelog

All notable changes to this project will be documented in this file.
Format based on [Keep a Changelog](https://keepachangelog.com/).

---

## [1.1.1] — 2026-04-08

### Bugfixes, Config Backup Skill Update, and Google Media Generation

Follow-up to v1.1.0 that closes two data-loss gaps discovered after release and ships the new Google Media Generation skill, a matching expert agent, and several template catalog improvements that landed between releases.

### Fixed
- **`config-backup` skill lost Knowledge System data** — the backup skill shipped in v1.1.0 did not know about the new enriched memory columns (`tags`, `entity_name`, `source`) or the `kg_entities` / `kg_relations` tables. Backups taken with the old skill silently dropped everything the v1.1.0 Knowledge System introduced. The skill is now bumped to `1.1.0` and saves:
  - `memory_long.tags`, `memory_long.entity_name`, `memory_long.source`
  - full `kg_entities` table (with UUID primary keys so relations can be restored)
  - full `kg_relations` table, ordered after `kg_entities` so foreign keys resolve on restore
  - backup format version bumped to `1.1` (old `1.0` backups remain restore-compatible)
- **`soul.proactive` silently wiped on `setup.sh --force`** — when a custom persona was set, the personalization block explicitly cleared the `PROACTIVE` variable before writing the `soul` table. The proactive/reactive choice from the setup menu was therefore discarded on every re-deploy, leaving the agent without any proactive-behavior instruction in its system prompt. Custom persona (tone/role) and proactive behavior (initiative style) are now treated as independent settings.
- **`google-media-gen` video generation timeout** — long-running Veo 3.1 video jobs exceeded the MCP tool-call timeout. Video generation is now split into a `generate_video` call that starts the job and a separate `wait_for_video` call that polls for completion.

### Added
- **New skill: Google Media Generation** — Nano Banana Pro for image generation/editing and Veo 3.1 for video generation and image-to-video animation. Tools: `generate_image`, `edit_image`, `generate_video`, `animate_image`, `wait_for_video`.
- **New expert agent: `google-media-prompter`** — specialized sub-agent for prompt engineering around Google's generative media models. Install via the Agent Library.
- **New category: `creativity`** — template catalog gained a dedicated category for generative media and creative tooling. `google-media-gen` moved out of `utilities`.
- **Tested column in skill catalog** — `n8n-claw-templates/README.md` now shows which skills have been smoke-tested on a live instance.
- **Keep-current for proactive setting** — `setup.sh --force` now reads the existing `soul.proactive` content from the DB and offers "Choose [keep current]" as the default, so manual DB edits to that row survive re-runs.
- **Custom → preset reset** — the custom persona prompt now accepts `reset` as an explicit way to drop the current custom persona and fall back to the preset selected via the Style menu. Previously there was no path from a custom persona back to a preset without direct DB editing.

### Upgrade from v1.1.0
```bash
cd n8n-claw && git pull && ./setup.sh --force
```
Then update the affected skills via chat:
- `update config-backup` — required to back up Knowledge System data
- `install google-media-gen` — optional, if you want Nano Banana / Veo 3.1
- `install agent google-media-prompter` — optional, expert prompter for the above

If your `soul.proactive` row was wiped by the old bug, re-running `setup.sh --force` and keeping the default choice will seed it with the proactive-behavior text.

---

## [1.1.0] — 2026-04-07

### Knowledge System & Bug Fixes

The agent now builds structured knowledge automatically — enriched memories with tags, entity tracking, auto-expiry, and a full knowledge graph with relationship mapping.

### Added
- **Enriched Memory** — memories now include tags (English lowercase keywords), entity names, and source tracking
- **Knowledge Graph** — new `kg_entities` and `kg_relations` tables for tracking people, companies, projects, events, and their relationships
- **Entity Manager** tool — search, save, update, relate, graph traversal, delete entities and relations
- **Auto-expiry** — memories expire based on category and importance (contact/preference/decision never expire, others after 90–180 days)
- **Memory Consolidation upgrade** — nightly job now extracts tags and entity names via LLM, sets auto-expiry, and cleans up expired entries
- **Proactive memory search** — agent searches memory before responding for better contextual answers
- **MCP connection guide** — docs for connecting Claude Code, Claude Desktop, and Cursor
- **New skills**: Config Backup, Lexware Office

### Fixed
- **`$` sign crash in conversations** (#26) — replaced Postgres nodes with PostgREST for Save Conversation and Log, eliminating pg-promise `$N` parameter interpretation
- **Hidden input hint** (#25) — setup now shows "(input is hidden for security)" when entering API keys. Thanks @LukasRegniet!
- **Umlaut handling** — `normalize()` transliterates ä→ae, ö→oe, ü→ue, ß→ss instead of stripping them
- **Recursive CTE** — graph traversal restructured for PostgreSQL 15 compatibility
- **Migration idempotency** — `004_knowledge.sql` drops both old and new function signatures

### Upgrade from v1.0.0
```bash
cd n8n-claw && git pull && ./setup.sh --force
```
`--force` is required for the new workflow tools (Entity Manager, updated Memory Save).

---

## [1.0.0] — 2026-04-05

### Multi-Provider, Zero Config

n8n-claw is now fully model-agnostic. Choose your LLM provider during setup and everything works out of the box — no manual node swapping, no credential juggling. This release also streamlines the installation to a 2-step process: clone & run, then chat.

### Added
- **LLM Provider Abstraction** — setup.sh automatically patches all LLM nodes in every workflow to match your chosen provider before importing
- **8 supported providers**: Anthropic, OpenAI, OpenRouter, DeepSeek, Google Gemini, Mistral, Ollama, OpenAI-compatible
- **Mistral AI** as new provider option
- **Provider switching** via `./setup.sh --force` — re-imports all workflows with new provider nodes
- **Credential PATCH** — existing credentials are updated with current API keys on re-run (instead of reusing stale data)
- **Telegram webhook fix** — second deactivate/activate cycle at end of setup ensures reliable webhook registration on fresh install
- **Ollama model prompt** — interactive model selection during setup
- **File delivery pipeline** — agent can send files (PDFs, images, documents) back to users via `[send_file:]` markers

### Changed
- **Default models updated**: OpenAI → `gpt-5.4`, Gemini → `gemini-3-flash-preview`, Ollama → `glm-4.7-flash`
- **README simplified** — installation reduced to 2 steps (clone & run → chat), removed manual credential setup instructions
- **Memory Consolidation** reads LLM provider config from `tools_config` at runtime (works with any provider)

### Fixed
- Gemini credential type corrected to `googlePalmApi` (matches n8n node expectation)
- OpenRouter default model corrected to `anthropic/claude-sonnet-4-6`
- Connection traversal in LLM node patch for nested workflow structures

### Upgrade from v0.17.0
```bash
cd n8n-claw && git pull && ./setup.sh --force
```
Choose your provider when prompted. All workflows will be re-imported with the correct LLM nodes.

---

## Previous Releases (v0.1.0 – v0.17.0)

### [0.17.0] — 2026-04-03 — File Bridge: Binary File Passthrough
New File Bridge microservice for binary file handling between Telegram, cloud storage, and the agent. Skills (Seafile, Google Drive, Nextcloud) now support upload and download of actual files.

### [0.16.0] — 2026-03-27 — Google OAuth2 & Google Skills
OAuth2 authorization flow via Telegram. Four new Google skills: Gmail, Calendar, Analytics, Ads. Fixed cartesian product bug in agent workflow.

### [0.15.0] — 2026-03-23 — OpenClaw Integration & New MCP Skills
OpenClaw integration (autonomous Linux agent), NocoDB CRM, Vikunja task management. Logo and social preview added.

### [0.14.0] — 2026-03-20 — Webhook API & External Integrations
HTTP webhook endpoint for Slack, Teams, Paperclip, and custom apps. Unified adapter workflow with multi-system support.

### [0.13.0] — 2026-03-19 — Heartbeat Extension
Recurring scheduled actions, Background Checker for silent monitoring, notify_mode control. Email Bridge with IMAP search.

### [0.12.0] — 2026-03-15 — Expert Agents
Sub-agent system with dynamic personas. Agent Library Manager for installing expert agents from catalog. 85+ expert agents available.

### [0.11.0] — 2026-03-14 — Crawl4AI Web Reader
Self-hosted web reader with JavaScript rendering. New MCP skills.

### [0.10.0] — 2026-03-10 — Project Memory & Scheduled Actions
Project document management, scheduled agent actions, reminder system rewrite, Email Bridge microservice, dynamic MCP server loading.

### [0.9.0] — 2026-03-10 — Scheduled Actions & Reminders
Single reminder workflow, auto-cleanup, dynamic MCP loading.

### [0.8.0] — 2026-03-10 — Reminder System
Unified reminder workflow replacing per-reminder approach.

### [0.7.0] — 2026-03-08 — Credential Flow & MCP Templates
Secure credential form for MCP skill API keys. One-time tokens with 10-min TTL. MCP template registry via CDN.

### [0.6.0] — 2026-03-07 — MCP Template Registry
Skill catalog with CDN delivery. Library Manager for install/remove.

### [0.5.0] — 2026-03-06 — Self-Hosted Web Search
SearXNG integration for private web search.

### [0.4.0] — 2026-03-06 — Media Handling
Photo, document, voice message, and location support in Telegram.

### [0.3.0] — 2026-03-06 — Heartbeat & Task Management
Proactive heartbeat, task management, morning briefing.

### [0.2.0] — 2026-03-06 — RAG Pipeline & Memory
Vector embeddings for semantic memory search. Memory consolidation workflow.

### [0.1.0] — 2026-03-05 — First Release
Core agent with Telegram interface, long-term memory, conversation history, MCP Builder, personality system.
