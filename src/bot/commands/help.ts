import { Message } from "discord.js";
import { getUser } from "../db";
import { isOwner } from "../config";

export async function helpCommand(msg: Message) {
  const user = getUser(msg.author.id);
  const owner = isOwner(msg.author.id);

  const generalFields = [
    { name: "`.help`", value: "Show this command list.", inline: false },
    { name: "`.l <lua code>`", value: "Convert Luau → Lua 5.3. Accepts code block, file upload, or reply.", inline: false },
    { name: "`.detect <lua code>`", value: "Detect obfuscator used and analyze the obfuscation.", inline: false },
    { name: "`.obf <lua code>`", value: "Obfuscate your Lua code.", inline: false },
    { name: "`.info [@user]`", value: "Show your info (role, tokens, commands used, blacklist). Mention a user to check theirs.", inline: false },
    { name: "`.gift @user <amount>`", value: "Gift tokens to another user in the server.", inline: false },
  ];

  const ownerFields = [
    { name: "`.bl <userId> <duration> <reason>`", value: "Blacklist a user. Duration: `1h`, `1d`, `7d`, `perm`, `-` = permanent. Use `-` for no reason.", inline: false },
    { name: "`.setrole @user <free|premium|owner>`", value: "Set a user's role.", inline: false },
    { name: "`.settoken @user <amount>`", value: "Set a user's token balance.", inline: false },
    { name: "`.settoken config <key> <value>`", value: "Update bot token config. Keys: `free_default`, `premium_default`, `free_max`, `premium_max`, `restore_amount`.", inline: false },
    { name: "`.config`", value: "View current bot configuration.", inline: false },
  ];

  const roleLabel = user.role === "owner" ? "👑 Owner" : user.role === "premium" ? "💎 Premium" : "🆓 Free";
  const tokenDisplay = user.role === "owner" ? "Unlimited ♾️" : String(user.tokens);

  const embed = {
    color: user.role === "owner" ? 0xf1c40f : user.role === "premium" ? 0x9b59b6 : 0x5865f2,
    title: "📋 Command List",
    description: `Your role: **${roleLabel}** · Tokens: **${tokenDisplay}**\nCommands cost **1 token** each. Tokens restore **+1 every hour**.`,
    fields: owner ? [...generalFields, { name: "\u200b", value: "**— Owner Commands —**", inline: false }, ...ownerFields] : generalFields,
    footer: { text: "Lua Dumper Bot • 24/7 Online" },
  };

  await msg.reply({ embeds: [embed] });
}
