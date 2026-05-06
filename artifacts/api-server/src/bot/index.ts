import { Client, GatewayIntentBits, Partials } from "discord.js";
import { logger } from "../lib/logger";
import { handleMessage } from "./handler";
import { startTokenRestore } from "./db";
import { startAutoUpdate } from "./autoupdate";
import { persistDb } from "./commands/lua";

let client: Client | null = null;

// ── FIX 2: Centralized graceful shutdown — satu tempat untuk semua handler ──
// Ditempatkan di sini agar tidak ada double-exit jika lua.ts juga punya handler.
let isShuttingDown = false;

function gracefulShutdown(signal: string) {
  if (isShuttingDown) return;
  isShuttingDown = true;
  logger.info({ signal }, "Graceful shutdown: menyimpan data...");
  try {
    persistDb();
    logger.info("userDb berhasil di-persist sebelum exit.");
  } catch (e) {
    logger.error({ e }, "Gagal persist userDb saat shutdown");
  }
  process.exit(0);
}

process.on("SIGTERM", () => gracefulShutdown("SIGTERM"));
process.on("SIGINT",  () => gracefulShutdown("SIGINT"));

export function startBot() {
  const token = process.env["DISCORD_BOT_TOKEN"];
  if (!token) {
    logger.error("DISCORD_BOT_TOKEN is not set — bot will not start");
    return;
  }

  const isProd = process.env["NODE_ENV"] === "production";
  const forceEnable = process.env["BOT_ENABLED"] === "true";
  if (!isProd && !forceEnable) {
    logger.info("Skipping bot startup in development — set BOT_ENABLED=true to enable locally");
    return;
  }

  client = new Client({
    intents: [
      GatewayIntentBits.Guilds,
      GatewayIntentBits.GuildMessages,
      GatewayIntentBits.MessageContent,
      GatewayIntentBits.DirectMessages,
      GatewayIntentBits.GuildMembers,
    ],
    partials: [Partials.Channel, Partials.Message],
  });

  client.once("clientReady", (c) => {
    logger.info({ tag: c.user.tag }, "Discord bot is online");
    startTokenRestore();
    startAutoUpdate(c);
  });

  client.on("messageCreate", handleMessage);

  client.on("error", (err) => {
    logger.error({ err }, "Discord client error");
  });

  client.on("warn", (info) => {
    logger.warn({ info }, "Discord client warning");
  });

  client.on("shardReconnecting", () => {
    logger.info("Discord shard reconnecting...");
  });

  client.on("shardResume", () => {
    logger.info("Discord shard resumed");
  });

  process.on("unhandledRejection", (err) => {
    logger.error({ err }, "Unhandled promise rejection");
  });

  client.login(token).catch((err) => {
    logger.error({ err }, "Failed to login to Discord");
    process.exit(1);
  });
}

export function getClient() {
  return client;
}
