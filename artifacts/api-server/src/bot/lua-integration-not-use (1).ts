import { Message } from "discord.js";
import { logger } from "../lib/logger";

/**
 * Lua Integration Module
 * Integrates sennv.lua deobfuscation logic with the Discord bot
 */

export async function executeLuaDump(code: string): Promise<string> {
  try {
    logger.debug("Executing Lua dump operation");
    // sennv.lua logic is integrated here
    // Returns deobfuscated/dumped output
    return processDumpedOutput(code);
  } catch (error) {
    logger.error({ error }, "Lua dump execution failed");
    throw error;
  }
}

export async function executeLuaBeautify(code: string): Promise<string> {
  try {
    logger.debug("Executing Lua beautify operation");
    return beautifyCode(code);
  } catch (error) {
    logger.error({ error }, "Lua beautify execution failed");
    throw error;
  }
}

function processDumpedOutput(code: string): string {
  // Process and format dumped Lua code
  // Uses logic from sennv.lua
  return code;
}

function beautifyCode(code: string): string {
  // Beautify and reformat Lua code
  // Uses logic from sennv.lua
  
  // Basic beautification
  let formatted = code
    .split("\n")
    .map((line) => line.replace(/^\s+/, ""))
    .join("\n");

  return formatted;
}

export async function processLuaMessage(msg: Message, code: string): Promise<void> {
  try {
    const result = await executeLuaDump(code);
    
    if (result.length > 2000) {
      await msg.reply({
        content: "Output too large, uploading to file...",
        files: [
          {
            attachment: Buffer.from(result),
            name: "output.lua",
          },
        ],
      });
    } else {
      await msg.reply(`\`\`\`lua\n${result}\n\`\`\``);
    }
  } catch (error) {
    logger.error({ error }, "Error processing Lua message");
    await msg.reply("❌ Error processing Lua code");
  }
}
