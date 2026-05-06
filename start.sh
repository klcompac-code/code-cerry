#!/bin/bash
export PATH="/home/runner/workspace/node_modules/.bin:/home/runner/.local/bin:$PATH"
exec ts-node --transpile-only src/index.ts
