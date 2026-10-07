#!/usr/bin/env bash
# Every suite. The game-backed tests read DIRT3_DIR (see tests/game.odin) and
# skip without it.
set -euo pipefail
cd "$(dirname "$0")"
odin test tests
