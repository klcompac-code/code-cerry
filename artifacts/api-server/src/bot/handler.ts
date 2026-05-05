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

import { logger } from "../lib/logger";
import { config } from "./config";

// Integrate Python and Lua modules
import { 
  checkRateLimit, 
  processLuaCode, 
  extractCodeFromMessage, 
  sendFormattedResponse, 
  isValidUrl 
} from "./python-integration";
import { executeLuaDump, executeLuaBeautify, processLuaMessage } from "./lua-integration";

const TOKEN_COMMANDS = new Set([".l", ".detect", ".obf", ".gift"]);

export async function handleMessage(msg: Message) {
  if (msg.author.bot) return;
  if (!msg.content.startsWith(".")) return;

  const cmd = msg.content.split(/\s+/)[0].toLowerCase();

  // Rate limit check for token-consuming commands
  const cooldown = checkRateLimit(msg.author.id);
  if (cooldown > 0 && TOKEN_COMMANDS.has(cmd)) {
    await msg.reply(`⏳ Please wait **${cooldown.toFixed(1)}s** before using this command again.`);
    return;
  }

  const isDm = !msg.guild;
  if (isDm && !config.allowDmCommands) {
    await msg.reply("❌ Commands can only be used inside a server, not in DMs.");
    return;
  }

  if (isBlacklisted(msg.author.id) && cmd !== ".info") {
    await msg.reply("🚫 You are blacklisted and cannot use this bot.");
    return;
  }

  if (TOKEN_COMMANDS.has(cmd) && !hasTokens(msg.author.id)) {
    await msg.reply("❌ You don't have enough tokens. Tokens restore **+1 every hour**. Use `.info` to check your balance.");
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
      default:
        break;
    }
  } catch (err) {
    logger.error({ err, cmd }, "Error handling command");
    try {
      await msg.reply("❌ An error occurred while processing your command.");
    } catch {}
  }
}
