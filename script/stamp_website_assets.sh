#!/usr/bin/env bash
# Re-stamps website/index.html with content hashes of styles.css and app.js
# (e.g. styles.css?v=1a2b3c4d) so browsers fetch fresh copies after a deploy
# instead of reusing a cached stylesheet with new HTML. Run after editing either file.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../website"
css="$(shasum styles.css | cut -c1-8)"
js="$(shasum app.js | cut -c1-8)"
sed -i '' -E "s#href=\"styles\.css(\?v=[0-9a-f]+)?\"#href=\"styles.css?v=$css\"#; s#src=\"app\.js(\?v=[0-9a-f]+)?\"#src=\"app.js?v=$js\"#" index.html
grep -nE 'styles\.css|app\.js' index.html
