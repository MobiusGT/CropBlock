#!/bin/zsh
# Snapshots of every state in light and dark, with seed data, on a fresh test store.
# Usage: tools/snap.sh            all pages
#        APP_SNAPSHOT_PAGES=empty,detected tools/snap.sh
#        tools/snap.sh -AppleShowScrollBars Always
set -u
app="$HOME/Applications/CropBlock.app/Contents/MacOS/CropBlock"
store="/tmp/CropBlock-test-store"
shots="/tmp/CropBlock-shots"
rm -rf "$HOME/Library/Saved Application State/io.github.mobiusgt.cropblock.savedState"
rm -rf "$store" "$shots"
APP_STORE="$store" APP_SEED=1 APP_SNAPSHOT="$shots" "$app" "$@"
