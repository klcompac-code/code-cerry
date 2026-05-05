import { Message } from "discord.js";
import { config, isOwner } from "../config";

export async function configCommand(msg: Message) {
  if (!isOwner(msg.author.id)) {
    await msg.reply("🚫 Only bot owners can use this command.");
    return;
  }

  const embed = {
    color: 0xe67e22,
    title: "⚙️ Bot Configuration",
    fields: [
      { name: "Free Default Tokens",    value: String(config.freeDefaultTokens),    inline: true },
      { name: "Premium Default Tokens", value: String(config.premiumDefaultTokens), inline: true },
      { name: "\u200b",                 value: "\u200b",                            inline: true },
      { name: "Free Max Tokens",        value: String(config.freeMaxTokens),        inline: true },
      { name: "Premium Max Tokens",     value: String(config.premiumMaxTokens),     inline: true },
      { name: "\u200b",                 value: "\u200b",                            inline: true },
      { name: "Token Restore Amount",   value: `+${config.tokenRestoreAmount} / hour`, inline: true },
      { name: "Allow DM Commands",      value: config.allowDmCommands ? "✅ Yes" : "❌ No", inline: true },
      { name: "Anti-Vuln (os/io)",      value: "✅ Always Active", inline: true },
    ],
    description:
      "Use `.settoken config <key> <value>` to update numbers.\n" +
      "Use `.setconfig <key> <true|false>` to toggle boolean settings.\n\n" +
      "Number keys: `free_default` · `premium_default` · `free_max` · `premium_max` · `restore_amount`\n" +
      "Toggle keys: `allow_dm`",
    footer: { text: "Lua Dumper Bot • Owner Panel" },
  };

  await msg.reply({ embeds: [embed] });
}
