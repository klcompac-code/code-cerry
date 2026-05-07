import { Message } from "discord.js";
import { getUser, saveUser, UserRole } from "../db";
import { config, isOwner } from "../config";

export async function setRoleCommand(msg: Message) {
  if (!isOwner(msg.author.id)) {
    await msg.reply("🚫 Only bot owners can use this command.");
    return;
  }

  const parts = msg.content.split(/\s+/);
  const mentioned = msg.mentions.users.first();
  const roleArg = parts.find((p) => ["owner", "premium", "free"].includes(p.toLowerCase()));

  if (!mentioned || !roleArg) {
    await msg.reply("Usage: `.setrole @user <free|premium|owner>`");
    return;
  }

  const role = roleArg.toLowerCase() as UserRole;
  const user = getUser(mentioned.id);
  const oldRole = user.role;
  user.role = role;

  if (role === "owner") {
    user.tokens = Infinity;
  } else if (role === "premium" && oldRole !== "premium") {
    user.tokens = config.premiumDefaultTokens;
  } else if (role === "free" && oldRole !== "free") {
    user.tokens = config.freeDefaultTokens;
  }

  saveUser(user);

  const roleColors: Record<UserRole, number> = {
    owner: 0xf1c40f,
    premium: 0x9b59b6,
    free: 0x3498db,
  };

  const embed = {
    color: roleColors[role],
    title: "🎭 Role Updated",
    fields: [
      { name: "User", value: `${mentioned.username} (${mentioned.id})`, inline: true },
      { name: "New Role", value: role.charAt(0).toUpperCase() + role.slice(1), inline: true },
      {
        name: "Tokens",
        value: role === "owner" ? "Unlimited" : String(user.tokens),
        inline: true,
      },
    ],
    footer: { text: `Updated by ${msg.author.username}` },
  };

  await msg.reply({ embeds: [embed] });
}
