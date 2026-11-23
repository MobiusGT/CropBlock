#!/bin/zsh
# Runs the in-app self-test against a fresh store in /tmp. Exit code 0 when every check passed.
set -u
rm -rf "$HOME/Library/Saved Application State/io.github.mobiusgt.cropblock.savedState"
store="/tmp/CropBlock-self-store"
rm -rf "$store"
APP_STORE="$store" "$HOME/Applications/CropBlock.app/Contents/MacOS/CropBlock" --selftest
