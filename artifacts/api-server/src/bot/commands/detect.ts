import { Message } from "discord.js";

function extractCode(msg: Message, prefix: string): string {
  const content = msg.content.slice(prefix.length).trim();
  const cbMatch = content.match(/^```(?:lua|luau)?\n?([\s\S]*?)```$/);
  if (cbMatch) return cbMatch[1].trim();
  return content;
}

interface ObfResult {
  name: string;
  confidence: string;
  indicators: string[];
}

function detectObfuscator(code: string): ObfResult {
  const indicators: string[] = [];
  let name = "Unknown";
  let confidence = "Low";

  const longVarNames = (code.match(/[a-zA-Z_][a-zA-Z0-9_]{20,}/g) || []).length;
  const hexEscapes = (code.match(/\\x[0-9a-fA-F]{2}/g) || []).length;
  const decimalEscapes = (code.match(/\\[0-9]{2,3}/g) || []).length;
  const tableHeavy = (code.match(/\{[^}]{0,10}\}/g) || []).length;
  const loadstrings = (code.match(/\bload\s*\(/g) || []).length;
  const repeatPatterns = /(.{8,})\1{3,}/.test(code);
  const garbageChars = (code.match(/[\x00-\x08\x0b\x0c\x0e-\x1f]/g) || []).length;
  const hasBase64 = /[A-Za-z0-9+/]{40,}={0,2}/.test(code);
  const xorPat = /\bbit\.bxor\b|\bxor\b/i.test(code);
  const hasReturn = /^return\s+/.test(code.trim());
  const bytePatterns = (code.match(/\\[0-9]{1,3}/g) || []).length;

  if (hexEscapes > 10 || decimalEscapes > 20) {
    indicators.push(`String encoding (${hexEscapes} hex escapes, ${decimalEscapes} decimal escapes)`);
    name = "Luraph / IronBrew-like";
    confidence = "Medium";
  }

  if (loadstrings > 2) {
    indicators.push(`${loadstrings} load() calls — multi-stage execution`);
    name = "IronBrew 2 / Custom VM";
    confidence = "High";
  }

  if (repeatPatterns) {
    indicators.push("Repeated byte patterns detected — possible VM bytecode");
    name = "Lua VM-based obfuscator";
    confidence = "High";
  }

  if (garbageChars > 5) {
    indicators.push(`${garbageChars} garbage/null characters — anti-decompile technique`);
  }

  if (hasBase64) {
    indicators.push("Base64-encoded payload detected");
    name = name === "Unknown" ? "Base64 wrapper" : name;
    confidence = "Medium";
  }

  if (xorPat) {
    indicators.push("XOR bitwise operation — possible encryption");
  }

  if (longVarNames > 10) {
    indicators.push(`${longVarNames} long/mangled variable names`);
    name = name === "Unknown" ? "Name mangler" : name;
    confidence = confidence === "Low" ? "Medium" : confidence;
  }

  if (tableHeavy > 30) {
    indicators.push("Heavy table usage — possible instruction dispatch table (VM)");
  }

  if (bytePatterns > 50) {
    indicators.push(`${bytePatterns} byte escape sequences — string obfuscation`);
  }

  if (hasReturn && loadstrings > 0) {
    indicators.push("Bytecode wrapper pattern (return load(...))");
    name = "Bytecode loader";
    confidence = "High";
  }

  if (indicators.length === 0) {
    indicators.push("No known obfuscation patterns detected");
    name = "Not obfuscated / Unknown";
    confidence = "Low";
  }

  return { name, confidence, indicators };
}

export async function detectCommand(msg: Message) {
  let code = "";

  if (msg.attachments.size > 0) {
    const att = msg.attachments.first()!;
    const res = await fetch(att.url);
    code = await res.text();
  } else if (msg.reference?.messageId) {
    const ref = await msg.channel.messages.fetch(msg.reference.messageId);
    code = ref.content;
  } else {
    code = extractCode(msg, ".detect");
  }

  if (!code.trim()) {
    await msg.reply("Usage: `.detect <lua code>` or upload a file, or reply to a message with code.");
    return;
  }

  const result = detectObfuscator(code);

  const confColor: Record<string, number> = {
    High: 0xe74c3c,
    Medium: 0xe67e22,
    Low: 0x2ecc71,
  };

  const embed = {
    color: confColor[result.confidence] ?? 0x95a5a6,
    title: "🔍 Obfuscation Detection",
    fields: [
      { name: "Detected Obfuscator", value: `\`${result.name}\``, inline: true },
      { name: "Confidence", value: result.confidence, inline: true },
      { name: "Code Size", value: `${code.length} chars`, inline: true },
      {
        name: "Indicators Found",
        value: result.indicators.map((i) => `• ${i}`).join("\n") || "None",
        inline: false,
      },
    ],
    footer: { text: "Lua Dumper Bot • Detection Engine v1.0" },
  };

  await msg.reply({ embeds: [embed] });
}
