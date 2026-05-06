import { Message } from "discord.js";
import { isBlacklisted, hasTokens, deductToken, incrementCommandsUsed } from "./db";
import { helpCommand } from "./commands/help";
import { luaCommand } from "./commands/lua";
import { detectCommand } from "./commands/detect";
import { obfCommand } from "./commands/obf";
import { infoCommand } from "./commands/info";
import { giftCommand } from "./commands/gift";
import { blacklistCommand } from "./commands/blacklist";
import { setRoleCommand } from "./commands/setrole";
import { setTokenCommand } from "./commands/settoken";
import { configCommand } from "./commands/configcmd";
import { setConfigCommand } from "./commands/setconfig";
import { setCoOwnerCommand } from "./commands/setcoowner";
import { logger } from "../lib/logger";
import { config, isPrivileged } from "./config";
import { confirmUpdate, denyUpdate } from "./autoupdate";
import { getClient } from "./index";

const TOKEN_COMMANDS = new Set([".l", ".detect", ".obf", ".gift"]);

export async function handleMessage(msg: Message) {
  if (msg.author.bot) return;
  if (!msg.content.startsWith(".")) return;

  const cmd = msg.content.split(/\s+/)[0].toLowerCase();

  const isDm = !msg.guild;

  if (isDm && !config.allowDmCommands && !isPrivileged(msg.author.id)) {
    await msg.reply("❌ Commands hanya bisa digunakan di dalam server, bukan di DM.");
    return;
  }

  if (isBlacklisted(msg.author.id) && cmd !== ".info") {
    await msg.reply("🚫 Kamu di-blacklist dan tidak bisa menggunakan bot ini.");
    return;
  }

  if (TOKEN_COMMANDS.has(cmd) && !hasTokens(msg.author.id)) {
    await msg.reply("❌ Token kamu tidak cukup. Token restore **+1 setiap jam**. Gunakan `.info` untuk cek saldo.");
    return;
  }

  try {
    switch (cmd) {
      case ".help":
        await helpCommand(msg);
        break;
      case ".l":
        await luaCommand(msg);
        deductToken(msg.author.id);
        incrementCommandsUsed(msg.author.id);
        break;
      case ".detect":
        await detectCommand(msg);
        deductToken(msg.author.id);
        incrementCommandsUsed(msg.author.id);
        break;
      case ".obf":
        await obfCommand(msg);
        deductToken(msg.author.id);
        incrementCommandsUsed(msg.author.id);
        break;
      case ".info":
        await infoCommand(msg);
        break;
      case ".gift":
        await giftCommand(msg);
        deductToken(msg.author.id);
        incrementCommandsUsed(msg.author.id);
        break;
      case ".bl":
        await blacklistCommand(msg);
        break;
      case ".setrole":
        await setRoleCommand(msg);
        break;
      case ".settoken":
        await setTokenCommand(msg);
        break;
      case ".config":
        await configCommand(msg);
        break;
      case ".setconfig":
        await setConfigCommand(msg);
        break;
      case ".setcoowner":
        await setCoOwnerCommand(msg);
        break;
      case ".confirm": {
        if (!isPrivileged(msg.author.id)) {
          await msg.reply("🚫 Hanya owner/co-owner yang bisa mengkonfirmasi update.");
          return;
        }
        const client = getClient();
        if (!client) { await msg.reply("❌ Bot client tidak tersedia."); return; }
        const result = await confirmUpdate(client, msg.author.id);
        await msg.reply(result);
        break;
      }
      case ".deny": {
        if (!isPrivileged(msg.author.id)) {
          await msg.reply("🚫 Hanya owner/co-owner yang bisa menolak update.");
          return;
        }
        const result = denyUpdate();
        await msg.reply(result);
        break;
      }
      default:
        break;
    }
  } catch (err) {
    logger.error({ err, cmd }, "Error handling command");
    try {
      await msg.reply("❌ Terjadi error saat memproses command kamu.");
    } catch {}
  }
}
