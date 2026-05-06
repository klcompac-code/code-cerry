# Discord Lua Bot (cerry-blue)

A Discord bot that obfuscates, beautifies, and analyzes Lua scripts, with a token-based usage system.

## Run & Operate

- **Start**: `node_modules/.bin/ts-node --transpile-only src/index.ts`
- **Required secrets**: `DISCORD_BOT_TOKEN`, `BOT_OWNER_IDS`, `BOT_ENABLED`
- **Optional secrets**: `GITHUB_PAT`, `GITHUB_REPO` (for auto-update), `DB_ENCRYPTION_KEY`
- **Env vars**: `PORT=3000`, `NODE_ENV=production`

## Stack

- Runtime: Node.js v20, TypeScript (via ts-node --transpile-only)
- Discord library: discord.js v14
- HTTP server: Fastify (health check endpoint)
- Logging: pino + pino-pretty

## Where things live

- `src/index.ts` — entry point, starts bot + HTTP server
- `src/app.ts` — Fastify HTTP server (health check)
- `src/bot/index.ts` — Discord client setup & lifecycle
- `src/bot/handler.ts` — message routing / command dispatch
- `src/bot/commands/` — individual command handlers
- `src/bot/db.ts` — in-memory user database
- `src/bot/config.ts` — bot config and role helpers
- `src/bot/autoupdate.ts` — GitHub-based auto-update system
- `src/lib/logger.ts` — pino logger instance

## Architecture decisions

- TypeScript compiled at runtime via `--transpile-only` (skips type checking for speed)
- In-memory user DB (persisted on SIGTERM/SIGINT via `persistDb()`)
- Token system: free users get 50 tokens, premium 500, restore +1/hr up to cap
- Auto-update checks GitHub for new commits and notifies owners via DM

## Product

- `.l` — obfuscate Lua script
- `.bf` — beautify Lua script
- `.get` — fetch and process Lua from URL
- `.detect` — detect obfuscation type
- `.obf` — obfuscate with Prometheus
- `.info` — show user token balance
- `.gift` — gift tokens to another user
- `.help` — command list
- Owner-only: `.bl`, `.setrole`, `.settoken`, `.setconfig`, `.setcoowner`

## User preferences

- Bot should run 24/7 as a persistent workflow

## Gotchas

- `src/app.ts` must export a `.listen(port, callback)` compatible interface
- Auto-update requires a git repo initialized at the workspace root
- `BOT_ENABLED=true` secret must be set for bot to start (bypasses dev-only check)

## Pointers

- Workflow skill: `.local/skills/workflows/SKILL.md`
- Secrets skill: `.local/skills/environment-secrets/SKILL.md`
