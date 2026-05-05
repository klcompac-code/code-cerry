import { Message, AttachmentBuilder } from "discord.js";
import { checkAntiVuln, formatBlockedMessage } from "../anti-vuln";

function extractCode(msg: Message, prefix: string): string {
  const content = msg.content.slice(prefix.length).trim();
  const cbMatch = content.match(/^```(?:lua|luau)?\n?([\s\S]*?)```$/);
  if (cbMatch) return cbMatch[1].trim();
  return content;
}

function obfuscate(code: string): string {
  const lines = code.split("\n");
  const obfLines: string[] = [];

  const junk = [
    `local _0x1 = math.floor(math.pi * 1000) % 7`,
    `local _0x2 = string.rep("\\0", 0)`,
    `local _0x3 = type({}) == "table" and 1 or 0`,
  ];

  obfLines.push(...junk);

  for (const line of lines) {
    if (line.trim().startsWith("--")) {
      obfLines.push(`-- ${Buffer.from(line.trim()).toString("base64")}`);
      continue;
    }
    let out = line;
    out = out.replace(/\blocal\s+(\w+)/g, (_m, name) => {
      const hex = Buffer.from(name).toString("hex").slice(0, 6);
      return `local _0x${hex}`;
    });
    obfLines.push(out);
  }

  const payload = Buffer.from(obfLines.join("\n")).toString("base64");
  return `-- Obfuscated by Lua Dumper Bot\nload((function(s) return (s:gsub("[^A-Za-z0-9+/=]","")) end)(${JSON.stringify(payload)}))()`;
}

export async function obfCommand(msg: Message) {
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
    rawCode = extractCode(msg, ".obf");
  }

  if (!rawCode.trim()) {
    await msg.reply("Usage: `.obf <lua code>` or upload a file, or reply to a message with code.");
    return;
  }

  // Anti-vuln: blokir os.* dan io.*
  const vulv = checkAntiVuln(rawCode);
  if (vulv.blocked) {
    await msg.reply(formatBlockedMessage(vulv));
    return;
  }

  const obfuscated = obfuscate(rawCode);

  if (obfuscated.length > 1900) {
    const buf = Buffer.from(obfuscated, "utf-8");
    const att = new AttachmentBuilder(buf, { name: "obfuscated.lua" });
    await msg.reply({ content: "Obfuscated output (sent as file):", files: [att] });
  } else {
    await msg.reply("```lua\n" + obfuscated + "\n```");
  }
}
