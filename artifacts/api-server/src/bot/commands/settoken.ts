import { Message } from "discord.js";
import { getUser, saveUser } from "../db";
import { config, isOwner } from "../config";

export async function setTokenCommand(msg: Message) {
  if (!isOwner(msg.author.id)) {
    await msg.reply("🚫 Only bot owners can use this command.");
    return;
  }

  const parts = msg.content.split(/\s+/);

  if (parts[1] === "config") {
    const key = parts[2];
    const val = parseInt(parts[3], 10);

    if (isNaN(val) || val < 0) {
      await msg.reply("Usage: `.settoken config <free_default|premium_default|free_max|premium_max|restore_amount> <value>`");
      return;
    }

    const keyMap: Record<string, keyof typeof config> = {
      free_default: "freeDefaultTokens",
      premium_default: "premiumDefaultTokens",
      free_max: "freeMaxTokens",
      premium_max: "premiumMaxTokens",
      restore_amount: "tokenRestoreAmount",
    };

    const configKey = keyMap[key];
    if (!configKey) {
      await msg.reply(`Unknown config key \`${key}\`. Valid keys: \`free_default\`, \`premium_default\`, \`free_max\`, \`premium_max\`, \`restore_amount\``);
      return;
    }

    (config as Record<string, number>)[configKey] = val;

    const embed = {
      color: 0x2ecc71,
      title: "⚙️ Config Updated",
      fields: [
        { name: "Key", value: `\`${key}\``, inline: true },
        { name: "New Value", value: String(val), inline: true },
      ],
      footer: { text: `Updated by ${msg.author.username}` },
    };

    await msg.reply({ embeds: [embed] });
    return;
  }

  const mentioned = msg.mentions.users.first();
  const amountStr = parts.find((p) => /^\d+$/.test(p));
  const amount = amountStr ? parseInt(amountStr, 10) : NaN;

  if (!mentioned || isNaN(amount)) {
    await msg.reply(
      "Usage:\n" +
      "• `.settoken @user <amount>` — set a user's tokens\n" +
      "• `.settoken config <key> <value>` — update config"
    );
    return;
  }

  const user = getUser(mentioned.id);
  if (user.role === "owner") {
    await msg.reply("Owners always have unlimited tokens.");
    return;
  }

  user.tokens = amount;
  saveUser(user);

  const embed = {
    color: 0x2ecc71,
    title: "🪙 Tokens Set",
    fields: [
      { name: "User", value: `${mentioned.username} (${mentioned.id})`, inline: true },
      { name: "Tokens", value: String(amount), inline: true },
    ],
    footer: { text: `Set by ${msg.author.username}` },
  };

  await msg.reply({ embeds: [embed] });
}
