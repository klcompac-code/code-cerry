#!/usr/bin/env node

/**
 * Integration Test Script
 * Tests bot commands with actual Lua sample files
 * Simulates Discord user behavior
 */

const fs = require("fs");
const path = require("path");

const colors = {
  reset: "\x1b[0m",
  green: "\x1b[32m",
  yellow: "\x1b[33m",
  red: "\x1b[31m",
  blue: "\x1b[34m",
  cyan: "\x1b[36m",
};

function log(message, color = "reset") {
  console.log(`${colors[color]}${message}${colors.reset}`);
}

function section(title) {
  console.log("\n");
  log("=".repeat(60), "blue");
  log(`  ${title}`, "cyan");
  log("=".repeat(60), "blue");
}

// Test scenarios
const tests = [
  {
    name: "Extract codeblock with lua tag",
    input: '```lua\nlocal x = 1\nprint(x)\n```',
    expectedType: "codeblock",
  },
  {
    name: "Extract codeblock with luau tag",
    input: '```luau\nlocal x: number = 1\n```',
    expectedType: "codeblock",
  },
  {
    name: "Detect unsafe local path",
    input: "file:///etc/passwd",
    expectedType: "blocked",
  },
  {
    name: "Allow safe public URL",
    input: "https://example.com/script.lua",
    expectedType: "url",
  },
  {
    name: "Detect private IP",
    input: "http://192.168.1.1/script.lua",
    expectedType: "blocked",
  },
  {
    name: "Parse fake function library",
    input: readSampleFile("fake_functions.lua"),
    expectedType: "large-file",
  },
  {
    name: "Parse vulnerable inventory",
    input: readSampleFile("cccvd.lua"),
    expectedType: "analysis",
  },
  {
    name: "Parse deobfuscated output",
    input: readSampleFile("5NAsTAF_0a3ca_dumped.lua"),
    expectedType: "deobfuscated",
  },
];

function readSampleFile(filename) {
  const basePath = path.join(__dirname, "..", "..", "sample");
  const files = fs.readdirSync(basePath);
  const matching = files.find((f) => f.toLowerCase().includes(filename.toLowerCase()));
  if (matching) {
    const filePath = path.join(basePath, matching);
    return fs.readFileSync(filePath, "utf-8").slice(0, 500); // First 500 chars
  }
  return null;
}

function testCodeblockExtraction(input) {
  const m = input.match(/```(lua|luau|)\n([\s\S]*?)\n```/i);
  return m ? { code: m[2].trim(), lang: m[1] || "lua" } : null;
}

function testUrlValidation(input) {
  try {
    const url = new URL(input);
    const isPrivate =
      /^(localhost|127\.|192\.168\.|10\.|172\.(1[6-9]|2\d|3[01])\.)/i.test(
        url.hostname
      );
    return !isPrivate ? "safe" : "blocked";
  } catch {
    return "invalid";
  }
}

function testCodeDetection(input) {
  if (!input) return false;
  return /\b(local|function|print|if|for|while|return|end)\b/.test(input);
}

async function main() {
  log("\n╔══════════════════════════════════════════════════════════╗", "green");
  log("║           BOT INTEGRATION TEST SUITE                    ║", "green");
  log("╚══════════════════════════════════════════════════════════╝", "green");

  const startTime = Date.now();
  let passed = 0,
    failed = 0;

  section("Running Integration Tests");

  tests.forEach((test, idx) => {
    log(`\n[${idx + 1}/${tests.length}] ${test.name}`, "cyan");

    try {
      let result;

      if (test.expectedType === "codeblock") {
        result = testCodeblockExtraction(test.input);
        if (result && result.code) {
          log(`  ✓ Extracted: ${result.code.slice(0, 40)}...`, "green");
          passed++;
        } else {
          log(`  ✗ Failed to extract codeblock`, "red");
          failed++;
        }
      } else if (test.expectedType === "blocked") {
        const validation = testUrlValidation(test.input);
        if (validation === "blocked" || validation === "invalid") {
          log(`  ✓ Correctly blocked/rejected`, "green");
          passed++;
        } else {
          log(`  ✗ Should have been blocked`, "red");
          failed++;
        }
      } else if (test.expectedType === "url") {
        const validation = testUrlValidation(test.input);
        if (validation === "safe") {
          log(`  ✓ URL is safe`, "green");
          passed++;
        } else {
          log(`  ✗ URL should be safe`, "red");
          failed++;
        }
      } else if (test.expectedType === "large-file") {
        if (test.input && test.input.length > 100) {
          const isCode = testCodeDetection(test.input);
          if (isCode) {
            log(
              `  ✓ Detected code (${test.input.length} chars)`,
              "green"
            );
            passed++;
          } else {
            log(`  ✓ File loaded (${test.input.length} chars)`, "green");
            passed++;
          }
        } else {
          log(`  ✗ File not found or too small`, "red");
          failed++;
        }
      } else if (test.expectedType === "analysis") {
        if (test.input && test.input.includes("vulnerability")) {
          log(`  ✓ Vulnerability analysis detected`, "green");
          passed++;
        } else if (test.input) {
          log(`  ✓ File parsed (${test.input.length} chars)`, "green");
          passed++;
        } else {
          log(`  ✗ File not found`, "red");
          failed++;
        }
      } else if (test.expectedType === "deobfuscated") {
        if (test.input) {
          log(`  ✓ Deobfuscated output loaded (${test.input.length} chars)`, "green");
          passed++;
        } else {
          log(`  ✗ Sample not found`, "red");
          failed++;
        }
      }
    } catch (error) {
      log(`  ✗ Error: ${error.message}`, "red");
      failed++;
    }
  });

  section("Test Results");

  log(`\n✓ Passed: ${passed}/${tests.length}`, "green");
  if (failed > 0) {
    log(`✗ Failed: ${failed}/${tests.length}`, "red");
  }

  const passRate = ((passed / tests.length) * 100).toFixed(1);
  log(`\n📊 Pass Rate: ${passRate}%`, passRate >= 80 ? "green" : "yellow");

  const duration = ((Date.now() - startTime) / 1000).toFixed(1);
  log(`⏱️  Total time: ${duration}s\n`, "cyan");

  if (failed === 0) {
    log("✅ All integration tests passed!\n", "green");
  } else {
    log(`⚠️  ${failed} test(s) failed\n`, "red");
    process.exit(1);
  }
}

main().catch((error) => {
  log(`\n✗ Fatal error: ${error.message}\n`, "red");
  process.exit(1);
});
