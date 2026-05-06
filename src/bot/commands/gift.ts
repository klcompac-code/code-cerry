import { Message } from "discord.js";
import { getUser, saveUser } from "../db";

export async function giftCommand(msg: Message) {
  const mentioned = msg.mentions.users.first();
  if (!mentioned) {
    await msg.reply("Usage: `.gift @user <amount>`");
    return;
  }

  const parts = msg.content.split(/\s+/);
  const amountStr = parts.find((p) => /^\d+$/.test(p));
  const amount = amountStr ? parseInt(amountStr, 10) : NaN;

  if (isNaN(amount) || amount <= 0) {
    await msg.reply("Please provide a valid positive token amount. Example: `.gift @user 50`");
    return;
  }

  if (mentioned.id === msg.author.id) {
    await msg.reply("You cannot gift tokens to yourself.");
    return;
  }

  const sender = getUser(msg.author.id);
  if (sender.tokens < amount) {
    await msg.reply(`You only have **${sender.tokens}** tokens. You cannot gift **${amount}**.`);
    return;
  }

  const receiver = getUser(mentioned.id);
  sender.tokens -= amount;
  receiver.tokens += amount;
  saveUser(sender);
  saveUser(receiver);

  const embed = {
    color: 0x2ecc71,
    title: "🎁 Token Gift",
    description: `**${msg.author.username}** gifted **${amount}** tokens to **${mentioned.username}**!`,
    fields: [
      { name: "Your Balance", value: String(sender.tokens), inline: true },
      { name: `${mentioned.username}'s Balance`, value: String(receiver.tokens), inline: true },
    ],
    footer: { text: "Lua Dumper Bot" },
  };

  await msg.reply({ embeds: [embed] });
}
