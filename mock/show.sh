#!/bin/zsh
# usage: ./show.sh [lit|saturated|plain] [light|dark]   — opens the Beam design mock in one of its scenes
cd "$(dirname "$0")"; pkill -f "Beam Mock.app/Contents/MacOS" 2>/dev/null; sleep 0.3
rm -rf ~/Library/Saved\ Application\ State/dev.beam.mock.savedState
args=(-scene "${1:-lit}"); [[ "${1:-lit}" == "lit" ]] && args+=(-jump 3); [[ -n "$2" ]] && args+=(-look "$2")
open "build/Beam Mock.app" --args "${args[@]}"
