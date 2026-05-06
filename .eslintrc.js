module.exports = {
  parser: "@typescript-eslint/parser",
  extends: [
    "eslint:recommended",
    "plugin:@typescript-eslint/recommended",
    "prettier"
  ],
  plugins: ["@typescript-eslint", "prettier"],
  env: {
    node: true,
    es2021: true,
    jest: true
  },
  rules: {
    "prettier/prettier": "error",
    "@typescript-eslint/explicit-function-return-types": [
      "warn",
      {
        allowExpressions: true,
        allowTypedFunctionExpressions: true
      }
    ],
    "@typescript-eslint/no-explicit-any": "warn",
    "@typescript-eslint/no-unused-vars": [
      "error",
      { argsIgnorePattern: "^_" }
    ],
    "no-console": [
      "warn",
      {
        allow: ["warn", "error", "info"]
      }
    ],
    "no-debugger": "warn",
    "prefer-const": "error",
    "no-var": "error"
  },
  overrides: [
    {
      files: ["tests/**/*"],
      rules: {
        "@typescript-eslint/no-explicit-any": "off"
      }
    }
  ]
};
