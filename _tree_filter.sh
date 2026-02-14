#!/bin/bash
# Remove CLAUDE.md from all commits
rm -f CLAUDE.md
# Fix gitignore comment in initial commit
if [ -f .gitignore ]; then
  sed -i 's/# Claude Code local settings/# Local settings/' .gitignore
fi
# Fix Claude Artifacts mention in DIAGRAM-PROMPT.md
if [ -f docs/DIAGRAM-PROMPT.md ]; then
  sed -i 's/ or AI image generators (DALL-E, Midjourney, Claude Artifacts)/ or AI image generators/' docs/DIAGRAM-PROMPT.md
fi
