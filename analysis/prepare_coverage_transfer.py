#!/usr/bin/env python3
"""Compatibility entry point for the corrected-GE transfer packer.

Use ``python analysis/coverage_transfer.py pack`` for new automation.
"""
from coverage_transfer import pack


if __name__ == "__main__":
    import json

    print(json.dumps(pack(), indent=2))
