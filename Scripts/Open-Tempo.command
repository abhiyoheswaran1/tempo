#!/bin/bash
set -euo pipefail
tempo_root="$(cd -- "$(dirname -- "$0")/.." && pwd)"
open -a Xcode "$tempo_root/Tempo.xcworkspace"
