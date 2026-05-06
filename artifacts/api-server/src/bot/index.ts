import { Client, GatewayIntentBits, Partials } from "discord.js";
import { logger } from "../lib/logger";
import { handleMessage } from "./handler";
import { startTokenRestore } from "./db";
import { startAutoUpdate } from "./autoupdate";

let client: Client | null = null;

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
