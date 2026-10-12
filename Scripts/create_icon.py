#!/usr/bin/env python3
"""Compatibility entry point for generating Tempo's vector brand assets."""
from pathlib import Path
import os
import subprocess
root = Path(__file__).resolve().parents[1]
environment = dict(os.environ)
environment.setdefault("DEVELOPER_DIR", "/Applications/Xcode.app/Contents/Developer")
subprocess.run(["xcrun", "swift", str(root / "Scripts/create_branding.swift")], cwd=root, env=environment, check=True)
