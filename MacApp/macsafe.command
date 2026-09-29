#!/bin/bash
# Opened by MacSafe.app → Storage → Open Terminal Dashboard
DIR="$(cd "$(dirname "$0")" && pwd)"
clear
exec /usr/bin/env python3 "$DIR/smcli.py" "$@"
