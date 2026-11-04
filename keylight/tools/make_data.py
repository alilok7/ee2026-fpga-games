#!/usr/bin/env python3
"""make_data.py - regenerate every data/*.mem file. Run after editing songs/ or text/."""
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
for script in ["gen_note_table.py", "song_to_mem.py", "font_to_mem.py", "strings_to_mem.py"]:
    subprocess.check_call([sys.executable, os.path.join(HERE, script)])
