#!/usr/bin/env python3
"""make_data.py - regenerate every data/*.mem file (and strings_map.vh).
Run after editing text/, or the tables in gen_tables.py / gen_sprites.py."""
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
for script in ["gen_tables.py", "gen_sprites.py", "fonts_to_mem.py", "strings_to_mem.py"]:
    subprocess.check_call([sys.executable, os.path.join(HERE, script)])
