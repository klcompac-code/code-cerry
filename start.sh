#!/bin/bash
export PATH="/home/runner/.local/bin:$PATH"
exec node_modules/.bin/ts-node --transpile-only src/index.ts
