#!/usr/bin/env python3
"""Turn the packer's id/version list into the index game.love ships.

One line of "<id>\t<version>" per bundled mod in, one JSON array out --  the
file src/mods/BundledMods.lua reads to know what this build carries and at
which version, without having to open a single .zip at startup.
"""
import json
import sys

rows = []
with open(sys.argv[1]) as fh:
    for line in fh:
        line = line.rstrip("\n")
        if not line:
            continue
        mod_id, version = line.split("\t")
        rows.append({"id": mod_id, "version": version,
                     "file": "bundled_mods/%s.zip" % mod_id})
with open(sys.argv[2], "w") as fh:
    json.dump(rows, fh)
