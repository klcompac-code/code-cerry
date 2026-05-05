import { Message, Attachment } from "discord.js";
import { logger } from "../lib/logger";

/**
 * Python Integration Module (senvielle.py)
 * Integrates Discord bot logic, Lua deobfuscation, and utilities
 */

export interface CommandOptions {
  stripComments?: boolean;
  renameVariables?: boolean;
  beautify?: boolean;
  fixSyntax?: boolean;
}

// Rate limiting
const userCooldowns = new Map<string, number>();
const RATE_LIMIT_SECONDS = 5;

export function checkRateLimit(userId: string): number {
  const now = Date.now();
  const lastUse = userCooldowns.get(userId) || 0;
  const elapsed = (now - lastUse) / 1000;

  if (elapsed < RATE_LIMIT_SECONDS) {
    return RATE_LIMIT_SECONDS - elapsed;
  }

  userCooldowns.set(userId, now);
  return 0;
}

/**
 * Process Lua code with various transformations
 */
export async function processLuaCode(
  code: string,
  options: CommandOptions
): Promise<string> {
  let processed = code;

  if (options.stripComments) {
    processed = stripComments(processed);
  }

  if (options.fixSyntax) {
    processed = fixLuaSyntax(processed);
  }

  if (options.renameVariables) {
    processed = renameVariables(processed);
  }

  if (options.beautify) {
    processed = beautifyLua(processed);
  }

  return processed;
}

function stripComments(code: string): string {
  // Remove single-line comments
  let result = code.replace(/--\[.*?\]/g, ""); // Block comments
  result = result.replace(/--.*$/gm, ""); // Line comments
  return result;
}

function fixLuaSyntax(code: string): string {
  // Fix common Lua syntax errors
  // - Missing 'do' blocks
  // - Extra 'end' statements
  // - Connection function formatting
  
  let result = code;
  
  // Fix 'for' without 'do'
  result = result.replace(/\bfor\s+(.+?)\s+then\b/g, "for $1 do");
  
  // Fix 'if' without 'then'
  result = result.replace(/\bif\s+(.+?)\s+do\b/g, "if $1 then");

  return result;
}

function renameVariables(code: string): string {
  // Intelligently rename variables based on type
  // Extract variable names and rename them more meaningfully
  
  const varMap = new Map<string, string>();
  let counter = 1;
  
  const varPattern = /\b([a-z_]\w*)\s*=/g;
  let result = code;
  
  let match;
  const regex = new RegExp(varPattern);
  while ((match = regex.exec(code)) !== null) {
    const varName = match[1];
    if (!varMap.has(varName)) {
      varMap.set(varName, `var${counter++}`);
    }
  }

  varMap.forEach((newName, oldName) => {
    result = result.replace(new RegExp(`\\b${oldName}\\b`, "g"), newName);
  });

  return result;
}

function beautifyLua(code: string): string {
  // Beautify Lua code with proper indentation
  let indent = 0;
  const lines = code.split("\n");
  const result: string[] = [];

  const openKeywords = /\b(function|if|for|while|repeat|do)\b/;
  const closeKeywords = /\b(end|until)\b/;

  for (const line of lines) {
    const trimmed = line.trim();
    
    if (!trimmed) {
      result.push("");
      continue;
    }

    if (closeKeywords.test(trimmed)) {
      indent = Math.max(0, indent - 1);
    }

    result.push("  ".repeat(indent) + trimmed);

    if (openKeywords.test(trimmed)) {
      indent++;
    }
  }

  return result.join("\n");
}

/**
 * Extract code from various sources (reply, file, URL)
 */
export async function extractCodeFromMessage(msg: Message): Promise<string | null> {
  // Check for code in message content
  const codeBlockMatch = msg.content.match(/```(?:lua)?\n?([\s\S]*?)\n?```/);
  if (codeBlockMatch) {
    return codeBlockMatch[1];
  }

  // Check for attachment
  if (msg.attachments.size > 0) {
    const attachment = msg.attachments.first() as Attachment;
    if (attachment.name?.endsWith(".lua")) {
      try {
        const response = await fetch(attachment.url);
        return await response.text();
      } catch (error) {
        logger.error({ error }, "Failed to fetch attachment");
        return null;
      }
    }
  }

  // Check for reply
  if (msg.reference) {
    try {
      const repliedTo = await msg.channel.messages.fetch(msg.reference.messageId!);
      return extractCodeFromMessage(repliedTo);
    } catch (error) {
      logger.error({ error }, "Failed to fetch replied message");
      return null;
    }
  }

  return null;
}

/**
 * Format and send response (handles Discord message limits)
 */
export async function sendFormattedResponse(
  msg: Message,
  content: string,
  title: string = "Result"
): Promise<void> {
  // Discord has 2000 character limit per message
  if (content.length <= 1980) {
    await msg.reply({
      content: `\`\`\`lua\n${content}\n\`\`\``,
      allowedMentions: { repliedUser: false },
    });
  } else {
    // Send as file if too large
    await msg.reply({
      files: [
        {
          attachment: Buffer.from(content, "utf-8"),
          name: `${title.toLowerCase().replace(/\s+/g, "_")}.lua`,
        },
      ],
      allowedMentions: { repliedUser: false },
    });
  }
}

/**
 * Validate URL for SSRF protection
 */
export function isValidUrl(url: string): boolean {
  try {
    const parsed = new URL(url);
    
    // Only allow http/https
    if (!["http:", "https:"].includes(parsed.protocol)) {
      return false;
    }

    const hostname = parsed.hostname || "";

    // Block local/internal addresses
    const blockedPatterns = [
      /^localhost$/i,
      /\.local$/i,
      /\.internal$/i,
      /^127\./,
      /^192\.168\./,
      /^10\./,
      /^172\.(1[6-9]|2\d|3[01])\./,
    ];

    return !blockedPatterns.some((pattern) => pattern.test(hostname));
  } catch {
    return false;
  }
}
