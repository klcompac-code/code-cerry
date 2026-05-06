export interface BotConfig {
  freeDefaultTokens: number;
  premiumDefaultTokens: number;
  tokenRestoreAmount: number;
  tokenRestoreIntervalMs: number;
  freeMaxTokens: number;
  premiumMaxTokens: number;
  allowDmCommands: boolean;
  blockOsLibrary: boolean;
  coOwnerIds: string[];
  autoUpdateEnabled: boolean;
  autoUpdateIntervalMs: number;
}

export const config: BotConfig = {
  freeDefaultTokens: 50,
  premiumDefaultTokens: 500,
  tokenRestoreAmount: 1,
  tokenRestoreIntervalMs: 60 * 60 * 1000,
  freeMaxTokens: 100,
  premiumMaxTokens: 1000,
  allowDmCommands: false,
  blockOsLibrary: true,
  coOwnerIds: (process.env["BOT_COOWNER_IDS"] ?? "").split(",").map((s) => s.trim()).filter(Boolean),
  autoUpdateEnabled: true,
  autoUpdateIntervalMs: 30 * 60 * 1000,
};

export function getOwnerIds(): string[] {
  return (process.env["BOT_OWNER_IDS"] ?? "").split(",").map((s) => s.trim()).filter(Boolean);
}

export function isOwner(userId: string): boolean {
  return getOwnerIds().includes(userId);
}

export function isCoOwner(userId: string): boolean {
  return config.coOwnerIds.includes(userId);
}

export function isPrivileged(userId: string): boolean {
  return isOwner(userId) || isCoOwner(userId);
}
