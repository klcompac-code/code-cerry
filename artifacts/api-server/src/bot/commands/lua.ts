import { Message, AttachmentBuilder } from "discord.js";
import { config } from "../config";

function extractCode(msg: Message, prefix: string): string {
  const content = msg.content.slice(prefix.length).trim();
  const cbMatch = content.match(/^```(?:lua|luau)?\n?([\s\S]*?)```$/);
  if (cbMatch) return cbMatch[1].trim();
  return content;
}

const BLOCKED_OS_PATTERNS = [
  /\bos\s*\.\s*exit\b/,
  /\bos\s*\.\s*execute\b/,
  /\bos\s*\.\s*remove\b/,
  /\bos\s*\.\s*rename\b/,
  /\bos\s*\.\s*tmpname\b/,
];

function checkBlockedLibraries(code: string): string | null {
  if (!config.blockOsLibrary) return null;
  for (const pat of BLOCKED_OS_PATTERNS) {
    if (pat.test(code)) {
      const match = code.match(pat);
      return `\`${match?.[0]}\``;
    }
  }
  return null;
}

function luauToLua53(code: string): string {
  let out = code;
  out = out.replace(/\bcontinue\b/g, "goto __continue__");
  out = out.replace(/\btask\.wait\b/g, "coroutine.yield");
  out = out.replace(/\btask\.spawn\b/g, "coroutine.wrap");
  out = out.replace(/\bstring\.split\s*\(([^,]+),\s*([^)]+)\)/g, (_m, s, sep) =>
    `(function(str,d) local t={} for p in str:gmatch("[^"..d.."]+") do t[#t+1]=p end return t end)(${s},${sep})`
  );
  return out;
}

export async function luaCommand(msg: Message) {
  let rawCode = "";

  if (msg.attachments.size > 0) {
    const att = msg.attachments.first()!;
    if (!att.name?.match(/\.(lua|luau|txt)$/i)) {
      await msg.reply("Please upload a `.lua`, `.luau`, or `.txt` file.");
      return;
    }
    const res = await fetch(att.url);
    rawCode = await res.text();
  } else if (msg.reference?.messageId) {
    const ref = await msg.channel.messages.fetch(msg.reference.messageId);
    rawCode = ref.content;
  } else {
    rawCode = extractCode(msg, ".l");
  }

  if (!rawCode.trim()) {
    await msg.reply("Usage: `.l <lua code>` or upload a `.lua` file, or reply to a message containing code.");
    return;
  }

  const blocked = checkBlockedLibraries(rawCode);
  if (blocked) {
    await msg.reply(`🚫 Kode mengandung fungsi yang diblokir: ${blocked}\nLibrary \`os\` (exit, execute, remove, rename) tidak diizinkan.`);
    return;
  }

  const converted = luauToLua53(rawCode);
  const output = `-- Converted to Lua 5.3 by Lua Dumper Bot\n${converted}`;

  if (output.length > 1900) {
    const buf = Buffer.from(output, "utf-8");
    const att = new AttachmentBuilder(buf, { name: "output.lua" });
    await msg.reply({ content: "Output is too large — sent as file:", files: [att] });
  } else {
    await msg.reply("```lua\n" + output + "\n```");
  }
}
