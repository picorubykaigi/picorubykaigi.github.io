#!/bin/zsh
# Build the Keynote template and the asset zip that the site hands out.
#
#   images/goodies/picorubykaigi2026-keynote.key         Keynote file (masters + sample slides)
#   images/goodies/picorubykaigi2026-keynote-assets.zip  PNG parts and backgrounds
#
# Intermediate files go to out/ (not committed). Keynote and the fonts used by
# the template must be installed on this Mac.
set -e
cd "$(dirname "$0")"
HERE="$PWD"
GOODIES="$HERE/../../images/goodies"
ASSETS=out/keynote

./export_assets.sh
ruby build_pptx.rb "$ASSETS" out/picorubykaigi2026.pptx
command rm -rf out/picorubykaigi2026.key out/keynote-check
mkdir -p out/keynote-check
osascript to_keynote.applescript "$HERE/out/picorubykaigi2026.pptx" "$HERE/out/picorubykaigi2026.key" "$HERE/out/keynote-check"
command cp -f out/picorubykaigi2026.key "$GOODIES/picorubykaigi2026-keynote.key"

# The zip carries each part under a name that says what it is.
PARTS=out/picorubykaigi2026-keynote-assets
command rm -rf "$PARTS"
mkdir -p "$PARTS"
command cp -f "$ASSETS/01-title-background.png" "$PARTS/background-title.png"
command cp -f "$ASSETS/02-about-me-background.png" "$PARTS/background-body.png"
command cp -f "$ASSETS/logo-lockup.png" "$PARTS/logo-title.png"
command cp -f "$ASSETS/logo-footer.png" "$PARTS/logo-footer.png"
command cp -f "$ASSETS/bullet-1.png" "$PARTS/bullet-1.png"
command cp -f "$ASSETS/bullet-2.png" "$PARTS/bullet-2.png"
command cp -f "$ASSETS/photo-frame.png" "$PARTS/photo-frame.png"
command cp -f "$ASSETS/code-tile.png" "$PARTS/code-panel.png"
command rm -f "$GOODIES/picorubykaigi2026-keynote-assets.zip"
(cd out && zip -q -X -r "$GOODIES/picorubykaigi2026-keynote-assets.zip" picorubykaigi2026-keynote-assets)

ls -la "$GOODIES"/picorubykaigi2026-keynote*
