#!/usr/bin/env bash
# Builds the web app and drops it into site/app/, ready to publish with the
# rest of site/ on GitHub Pages (https://chismosa-app.github.io/app/).
#
#   tool/build_web.sh
#
# site/app/ is git-ignored here: it is build output, and only the Pages repo
# (chismosa-app.github.io) needs it.
set -euo pipefail
cd "$(dirname "$0")/.."

flutter build web --release --base-href /app/ --no-wasm-dry-run

rm -rf site/app
cp -r build/web site/app
echo "Web app ready in site/app/. Copy site/ over the Pages repo and push."
