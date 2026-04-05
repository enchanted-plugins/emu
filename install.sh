#!/usr/bin/env bash
set -euo pipefail

ALLAY_DIR="${HOME}/.claude/plugins/allay"

if [[ -d "$ALLAY_DIR" ]]; then
  echo "Allay already installed at $ALLAY_DIR"
  echo "To update: cd $ALLAY_DIR && git pull"
  exit 0
fi

echo "Installing Allay..."
git clone https://github.com/allay-dev/allay "$ALLAY_DIR"
chmod +x "$ALLAY_DIR"/plugins/*/hooks/*/*.sh
chmod +x "$ALLAY_DIR"/shared/*.sh

echo ""
echo "Done. Run in Claude Code:"
echo ""
echo "  /plugin add $ALLAY_DIR/plugins/context-guard"
echo "  /plugin add $ALLAY_DIR/plugins/state-keeper"
echo "  /plugin add $ALLAY_DIR/plugins/token-saver"
echo ""
echo "Or add the marketplace:"
echo "  /plugin marketplace add $ALLAY_DIR"
echo ""
echo "Start with context-guard — it's the one you'll feel."
