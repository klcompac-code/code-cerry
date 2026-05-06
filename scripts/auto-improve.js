#!/usr/bin/env node

/**
 * Auto-Improve Script
 * Automatically improves code quality by:
 * - Running linter with auto-fix
 * - Formatting with prettier
 * - Running type checks
 * - Running tests
 * - Generating coverage report
 */

const { execSync } = require("child_process");
const fs = require("fs");
const path = require("path");

const colors = {
  reset: "\x1b[0m",
  bright: "\x1b[1m",
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
  log(`  ${title}`, "bright");
  log("=".repeat(60), "blue");
}

async function runCommand(cmd, description) {
  try {
    log(`\n→ ${description}...`, "cyan");
    execSync(cmd, { stdio: "inherit" });
    log(`✓ ${description} completed`, "green");
    return true;
  } catch (error) {
    log(`✗ ${description} failed`, "red");
    return false;
  }
}

async function main() {
  log("\n╔══════════════════════════════════════════════════════════╗", "bright");
  log("║           BOT AUTO-IMPROVE & QUALITY CHECK              ║", "bright");
  log("╚══════════════════════════════════════════════════════════╝", "bright");

  const startTime = Date.now();
  const results = {};

  // 1. Format code
  section("Step 1: Code Formatting");
  results.format = await runCommand(
    "npm run format",
    "Formatting with Prettier"
  );

  // 2. Lint with auto-fix
  section("Step 2: Linting & Auto-Fix");
  results.lint = await runCommand(
    "npm run lint:fix",
    "Running ESLint with auto-fix"
  );

  // 3. Type checking
  section("Step 3: TypeScript Type Checking");
  results.typeCheck = await runCommand(
    "npm run type-check",
    "Type checking with TypeScript"
  );

  // 4. Run tests
  section("Step 4: Unit Testing");
  results.tests = await runCommand("npm run test", "Running unit tests");

  // 5. Generate report
  section("Step 5: Quality Report");

  const srcDir = path.join(__dirname, "..", "src");
  const fileCount = countFiles(srcDir, [".ts"]);
  const lineCount = countLines(srcDir, [".ts"]);

  log(`\n📊 Code Statistics:`, "cyan");
  log(`   • TypeScript files: ${fileCount.ts}`, "yellow");
  log(`   • Total lines of code: ${lineCount.total}`, "yellow");
  log(`   • Average file size: ${Math.round(lineCount.total / fileCount.ts)} LOC`, "yellow");

  // 6. Summary
  section("Summary");

  let allPassed = true;
  const checks = [
    { name: "Formatting", result: results.format },
    { name: "Linting", result: results.lint },
    { name: "Type Checking", result: results.typeCheck },
    { name: "Unit Tests", result: results.tests },
  ];

  checks.forEach(({ name, result }) => {
    const status = result ? "✓ PASS" : "✗ FAIL";
    const statusColor = result ? "green" : "red";
    log(`   ${name.padEnd(20)} ${status}`, statusColor);
    if (!result) allPassed = false;
  });

  const duration = ((Date.now() - startTime) / 1000).toFixed(1);
  log(`\n⏱️  Total time: ${duration}s`, "cyan");

  if (allPassed) {
    log("\n✅ All quality checks passed! Code is ready.", "green");
    log("\n📝 Recommendations:", "yellow");
    log("   • Code is formatted and linted", "yellow");
    log("   • All type checks passed", "yellow");
    log("   • Unit tests passing", "yellow");
    log("   • Ready for commit/push", "yellow");
  } else {
    log("\n⚠️  Some checks failed. Please review above.", "red");
    process.exit(1);
  }

  log("\n");
}

function countFiles(dir, extensions) {
  const result = {};
  extensions.forEach((ext) => {
    result[ext.replace(".", "")] = 0;
  });

  function traverse(currentDir) {
    const files = fs.readdirSync(currentDir);
    files.forEach((file) => {
      const filePath = path.join(currentDir, file);
      const stat = fs.statSync(filePath);
      if (stat.isDirectory() && !file.startsWith(".")) {
        traverse(filePath);
      } else {
        extensions.forEach((ext) => {
          if (file.endsWith(ext)) {
            result[ext.replace(".", "")]++;
          }
        });
      }
    });
  }

  traverse(dir);
  return result;
}

function countLines(dir, extensions) {
  let total = 0;

  function traverse(currentDir) {
    const files = fs.readdirSync(currentDir);
    files.forEach((file) => {
      const filePath = path.join(currentDir, file);
      const stat = fs.statSync(filePath);
      if (stat.isDirectory() && !file.startsWith(".")) {
        traverse(filePath);
      } else {
        extensions.forEach((ext) => {
          if (file.endsWith(ext)) {
            const content = fs.readFileSync(filePath, "utf-8");
            total += content.split("\n").length;
          }
        });
      }
    });
  }

  traverse(dir);
  return { total };
}

main().catch((error) => {
  log(`\n✗ Fatal error: ${error.message}`, "red");
  process.exit(1);
});
