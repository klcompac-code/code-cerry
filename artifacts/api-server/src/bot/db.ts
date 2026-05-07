import { config, isOwner } from "./config";

export type UserRole = "owner" | "premium" | "free";

export interface UserRecord {
  userId: string;
  role: UserRole;
  tokens: number;
  commandsUsed: number;
  blacklisted: boolean;
  blacklistReason: string;
  blacklistExpiry: number | null;
}

const users = new Map<string, UserRecord>();

export function getUser(userId: string): UserRecord {
  if (!users.has(userId)) {
    const role: UserRole = isOwner(userId) ? "owner" : "free";
    const tokens = role === "owner" ? Infinity : config.freeDefaultTokens;
    users.set(userId, {
      userId,
      role,
      tokens,
      commandsUsed: 0,
      blacklisted: false,
      blacklistReason: "",
      blacklistExpiry: null,
    });
  }
  const user = users.get(userId)!;
  if (isOwner(userId) && user.role !== "owner") {
    user.role = "owner";
    user.tokens = Infinity;
    saveUser(user);
  }
  return user;
}

export function saveUser(record: UserRecord) {
  users.set(record.userId, record);
}

export function getAllUsers(): UserRecord[] {
  return Array.from(users.values());
}

export function isBlacklisted(userId: string): boolean {
  if (isOwner(userId)) return false;
  const user = getUser(userId);
  if (!user.blacklisted) return false;
  if (user.blacklistExpiry !== null && Date.now() > user.blacklistExpiry) {
    user.blacklisted = false;
    user.blacklistReason = "";
    user.blacklistExpiry = null;
    saveUser(user);
    return false;
  }
  return true;
}

export function hasTokens(userId: string): boolean {
  const user = getUser(userId);
  if (user.role === "owner") return true;
  return user.tokens > 0;
}

export function deductToken(userId: string) {
  const user = getUser(userId);
  if (user.role === "owner") return;
  user.tokens = Math.max(0, user.tokens - 1);
  saveUser(user);
}

export function incrementCommandsUsed(userId: string) {
  const user = getUser(userId);
  user.commandsUsed += 1;
  saveUser(user);
}

export function startTokenRestore() {
  setInterval(() => {
    for (const user of users.values()) {
      if (user.role === "owner") continue;
      const max = user.role === "premium" ? config.premiumMaxTokens : config.freeMaxTokens;
      if (user.tokens < max) {
        user.tokens = Math.min(max, user.tokens + config.tokenRestoreAmount);
        saveUser(user);
      }
    }
  }, config.tokenRestoreIntervalMs);
}
