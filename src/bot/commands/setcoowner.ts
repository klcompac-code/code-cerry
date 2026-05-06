import { Message } from "discord.js";
import { config, isOwner } from "../config";

export async function setCoOwnerCommand(msg: Message) {
  if (!isOwner(msg.author.id)) {
    await msg.reply("🚫 Hanya bot owner yang bisa menggunakan command ini.");
    return;
  }

  const parts = msg.content.split(/\s+/);
  const action = parts[1]?.toLowerCase();
  const targetId = parts[2]?.replace(/[<@!>]/g, "");

  if (!action || !targetId || !["add", "remove", "list"].includes(action)) {
    await msg.reply(
      "Usage:\n" +
      "`.setcoowner add <userId>` — tambah co-owner\n" +
      "`.setcoowner remove <userId>` — hapus co-owner\n" +
      "`.setcoowner list` — lihat daftar co-owner"
    );
    return;
  }

  if (action === "list") {
    const list = config.coOwnerIds.length
      ? config.coOwnerIds.map((id) => `<@${id}>`).join("\n")
      : "_Belum ada co-owner_";
    await msg.reply({ embeds: [{ color: 0x9b59b6, title: "👑 Co-Owner List", description: list }] });
    return;
  }

  if (action === "add") {
    if (config.coOwnerIds.includes(targetId)) {
      await msg.reply(`⚠️ <@${targetId}> sudah jadi co-owner.`);
      return;
    }
    config.coOwnerIds.push(targetId);
    await msg.reply({ embeds: [{ color: 0x2ecc71, title: "✅ Co-Owner Ditambahkan", description: `<@${targetId}> sekarang jadi co-owner.` }] });
    return;
  }

  if (action === "remove") {
    const idx = config.coOwnerIds.indexOf(targetId);
    if (idx === -1) {
      await msg.reply(`⚠️ <@${targetId}> bukan co-owner.`);
      return;
    }
    config.coOwnerIds.splice(idx, 1);
    await msg.reply({ embeds: [{ color: 0xe74c3c, title: "🗑️ Co-Owner Dihapus", description: `<@${targetId}> sudah bukan co-owner.` }] });
  }
}
