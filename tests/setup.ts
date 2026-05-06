// Test setup
process.env.NODE_ENV = "test";
process.env.BOT_OWNER_IDS = "123456789";
process.env.DB_ENCRYPTION_KEY = "test-key-for-testing-only";

// Suppress logger in tests
jest.mock("../src/lib/logger", () => ({
  logger: {
    info: jest.fn(),
    warn: jest.fn(),
    error: jest.fn(),
    debug: jest.fn(),
  },
}));
