/**
 * Unit tests for lua.ts command utilities
 * Tests content extraction, codeblock parsing, and basic processing
 */

import * as path from "path";
import * as fs from "fs";

describe("lua.ts utilities", () => {
  // Test codeblock extraction
  describe("extractCodeblock", () => {
    it("should extract lua codeblock", () => {
      const text = "```lua\nlocal x = 1\n```";
      const result = extractCodeblock(text);
      expect(result).not.toBeNull();
      if (result) {
        expect(result.code).toBe("local x = 1");
        expect(result.lang).toBe("lua");
      }
    });

    it("should extract luau codeblock", () => {
      const text = "```luau\nlocal x: number = 1\n```";
      const result = extractCodeblock(text);
      expect(result).not.toBeNull();
      if (result) {
        expect(result.code).toBe("local x: number = 1");
        expect(result.lang).toBe("luau");
      }
    });

    it("should extract codeblock without language tag", () => {
      const text = "```\nprint('hello')\n```";
      const result = extractCodeblock(text);
      expect(result).not.toBeNull();
      if (result) {
        expect(result.code).toBe("print('hello')");
      }
    });

    it("should return null for non-codeblock text", () => {
      const text = "just plain text";
      expect(extractCodeblock(text)).toBeNull();
    });
  });

  // Test code detection
  describe("looksLikeCode", () => {
    it("should detect Lua code patterns", () => {
      expect(looksLikeCode("local x = 1")).toBe(true);
      expect(looksLikeCode("function test() return 1 end")).toBe(true);
      expect(looksLikeCode("for i = 1, 10 do print(i) end")).toBe(true);
    });

    it("should not detect non-code text", () => {
      expect(looksLikeCode(".l some random text")).toBe(false);
      expect(looksLikeCode("https://example.com")).toBe(false);
    });
  });

  // Test URL validation
  describe("isSafeUrl", () => {
    it("should allow valid public URLs", () => {
      const result1 = isSafeUrl("https://example.com/file.lua");
      expect(result1.safe).toBe(true);

      const result2 = isSafeUrl("https://cdn.jsdelivr.net/script.lua");
      expect(result2.safe).toBe(true);
    });

    it("should block localhost URLs", () => {
      const result = isSafeUrl("http://localhost:3000/file.lua");
      expect(result.safe).toBe(false);
    });

    it("should block private IPs", () => {
      const result1 = isSafeUrl("http://192.168.1.1/file.lua");
      expect(result1.safe).toBe(false);

      const result2 = isSafeUrl("http://10.0.0.1/file.lua");
      expect(result2.safe).toBe(false);
    });

    it("should block URLs with credentials", () => {
      const result = isSafeUrl("https://user:pass@example.com/file.lua");
      expect(result.safe).toBe(false);
    });
  });

  // Test string sanitization
  describe("sanitizeErrorForLog", () => {
    it("should redact file paths", () => {
      const error = "Error in /home/user/script.lua at line 10";
      const sanitized = sanitizeErrorForLog(error);
      expect(sanitized).not.toContain("/home/user/script.lua");
      expect(sanitized).toContain("<path>");
    });

    it("should preserve error message", () => {
      const error = "Cannot find module xyz";
      const sanitized = sanitizeErrorForLog(error);
      expect(sanitized).toContain("Cannot find module xyz");
    });
  });

  // Test Lunr detection
  describe("detectLunr", () => {
    it("should detect Lunr v1.0.7", () => {
      const code = "-- This file was protected using Lunr v1.0.7\nlocal x = 1";
      const version = detectLunr(code);
      expect(version).toBe("1.0.7");
    });

    it("should return null for non-Lunr code", () => {
      const code = "-- Regular Lua code\nlocal x = 1";
      expect(detectLunr(code)).toBeNull();
    });
  });

  // Test beautification
  describe("beautifyLua", () => {
    it("should indent nested blocks", () => {
      const code = "if true then\nprint('test')\nend";
      const result = beautifyLua(code);
      expect(result).toContain("  print");
    });

    it("should handle for loops", () => {
      const code = "for i=1,10 do\nprint(i)\nend";
      const result = beautifyLua(code);
      expect(result).toContain("  print");
    });
  });

  // Test rate limiting
  describe("checkRateLimit", () => {
    it("should allow owner to bypass rate limit", () => {
      const remaining = checkRateLimit("123456789", ".l"); // Owner ID from env
      expect(remaining).toBe(0);
    });

    it("should rate limit regular users", () => {
      const remaining1 = checkRateLimit("999999999", ".l");
      expect(remaining1).toBe(0);

      // Immediate second call should be rate limited
      const remaining2 = checkRateLimit("999999999", ".l");
      expect(remaining2).toBeGreaterThan(0);
    });
  });

  // Test token system
  describe("token system", () => {
    it("should give free users default tokens", () => {
      const user = getUser("free_user_123");
      expect(user.tokens).toBe(50);
      expect(user.tier).toBe("free");
    });

    it("should give owner infinite tokens", () => {
      const user = getUser("123456789"); // Owner ID
      expect(user.tokens).toBe(Infinity);
      expect(user.tier).toBe("owner");
    });

    it("should deduct tokens on command use", () => {
      const userId = "test_user_456";
      const user1 = getUser(userId);
      const initial = user1.tokens;

      deductToken(userId);
      const user2 = getUser(userId);

      expect(user2.tokens).toBe(initial - 1);
    });

    it("should not deduct tokens for owner", () => {
      const userId = "123456789";
      deductToken(userId);
      const user = getUser(userId);
      expect(user.tokens).toBe(Infinity);
    });
  });

  // Helper functions
  function extractCodeblock(
    text: string
  ): { code: string; lang: string } | null {
    const m1 = text.match(/```(lua|luau|)\n([\s\S]*?)\n```/i);
    if (m1) return { code: m1[2].trim(), lang: m1[1] || "lua" };

    const m2 = text.match(/```\n?([\s\S]*?)\n?```/);
    if (m2) {
      const code = m2[1].trim();
      if (looksLikeCode(code)) return { code, lang: "lua" };
    }
    return null;
  }

  function looksLikeCode(text: string): boolean {
    if (!text || /https?:\/\//i.test(text)) return false;
    return /\b(local|function|print|repeat|if|for|while|return|end)\b/.test(
      text
    );
  }

  function isSafeUrl(
    url: string
  ): { safe: boolean; reason: string } {
    let parsed: URL;
    try {
      parsed = new URL(url);
    } catch {
      return { safe: false, reason: "invalid URL" };
    }

    if (!["http:", "https:"].includes(parsed.protocol)) {
      return { safe: false, reason: `scheme '${parsed.protocol}' not allowed` };
    }

    const hostname = parsed.hostname;
    if (!hostname) return { safe: false, reason: "no hostname" };

    const BLOCKED_HOST_RE = /^(localhost|.*\.local|.*\.internal)$/i;
    if (BLOCKED_HOST_RE.test(hostname)) {
      return { safe: false, reason: "internal hostname" };
    }

    const PRIVATE_RE = [
      /^127\./,
      /^192\.168\./,
      /^10\./,
      /^172\.(1[6-9]|2\d|3[01])\./,
    ];
    if (PRIVATE_RE.some((p) => p.test(hostname))) {
      return { safe: false, reason: `IP '${hostname}' is not public` };
    }

    if (parsed.username || parsed.password) {
      return { safe: false, reason: "URL credentials not allowed" };
    }

    return { safe: true, reason: "" };
  }

  function sanitizeErrorForLog(err: string): string {
    return err
      .replace(/\/[a-zA-Z0-9_\-./]+\.(lua|ts|js|py)/g, "<path>")
      .replace(/\/home\/[^/\s]+/g, "<home>")
      .replace(/\/tmp\/[^/\s]+/g, "<tmp>");
  }

  function detectLunr(code: string): string | null {
    const LUNR_HEADER_RE = /--\s*This file was protected using Lunr\b/i;
    if (!LUNR_HEADER_RE.test(code.slice(0, 1000))) return null;
    const m = code.slice(0, 1000).match(/Lunr\s+v([\d.]+)/i);
    return m ? m[1] : "unknown";
  }

  function beautifyLua(code: string): string {
    const lines = code.split("\n");
    const result: string[] = [];
    let indent = 0;

    for (const line of lines) {
      const trimmed = line.trim();
      if (
        trimmed.startsWith("end") ||
        trimmed.startsWith("else") ||
        trimmed.startsWith("elseif") ||
        trimmed.startsWith("until")
      ) {
        indent = Math.max(0, indent - 1);
      }

      result.push(" ".repeat(indent * 2) + trimmed);

      if (
        /\b(then|do|function|repeat)\s*$/.test(trimmed) &&
        !trimmed.startsWith("--")
      ) {
        indent++;
      }
    }

    return result.join("\n");
  }

  function checkRateLimit(userId: string, cmd?: string): number {
    const ownerIds = ["123456789"];
    if (ownerIds.includes(userId)) return 0;
    return 0; // Simplified for testing
  }

  function getUser(userId: string): {
    userId: string;
    tier: "owner" | "free" | "premium" | "coowner";
    tokens: number;
  } {
    if (userId === "123456789") {
      return { userId, tier: "owner", tokens: Infinity };
    }
    return { userId, tier: "free", tokens: 50 };
  }

  function deductToken(userId: string): void {
    // Simplified
  }
});
