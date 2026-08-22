#!/usr/bin/env python3

import dbus
import os
import re
import subprocess
import sys
import time
import datetime
from pathlib import Path

REPO = Path.home() / "fpga-rtl-portfolio"
VIDEO_DIR = REPO / "projects/zcu104/01-deterministic-event-control-engine/evidence/videos"
VIDEO_DIR.mkdir(parents=True, exist_ok=True)

stamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
raw = VIDEO_DIR / f"zcu104_ila_live_capture_{stamp}.webm"
mp4 = VIDEO_DIR / f"zcu104_ila_live_capture_{stamp}.mp4"

def run(cmd, capture=False):
    return subprocess.run(
        cmd,
        cwd=REPO,
        text=True,
        check=True,
        capture_output=capture
    )

if os.environ.get("XDG_SESSION_TYPE", "").lower() != "wayland":
    sys.exit("ERROR: Wayland session required.")

# Find visible Vivado windows.
result = run(
    ["xdotool", "search", "--onlyvisible", "--name", "Vivado"],
    True
)

ids = [x.strip() for x in result.stdout.splitlines() if x.strip()]

if not ids:
    sys.exit("ERROR: No visible Vivado window found.")

# Pick the largest visible Vivado window.
windows = []

for wid in ids:
    try:
        geo = run(
            ["xdotool", "getwindowgeometry", "--shell", wid],
            True
        ).stdout

        vals = dict(re.findall(r"^(X|Y|WIDTH|HEIGHT)=(-?\d+)$",
                               geo, re.MULTILINE))

        x = int(vals["X"])
        y = int(vals["Y"])
        width = int(vals["WIDTH"])
        height = int(vals["HEIGHT"])

        windows.append((width * height, wid, x, y, width, height))
    except Exception:
        pass

if not windows:
    sys.exit("ERROR: Could not determine Vivado geometry.")

_, wid, x, y, width, height = max(windows)

# H.264/yuv420p requires even dimensions.
width  = width  - (width  % 2)
height = height - (height % 2)

# Safety check: refuse suspiciously huge multi-monitor regions.
if width > 3000 or height > 1800:
    sys.exit(
        f"ERROR: Vivado capture region looks too large: "
        f"{width}x{height}. Recording aborted."
    )

print()
print("========================================")
print(" ZCU104 VIVADO-ONLY EVIDENCE RECORDER")
print("========================================")
print(f"Vivado window ID : {wid}")
print(f"Capture X        : {x}")
print(f"Capture Y        : {y}")
print(f"Capture width    : {width}")
print(f"Capture height   : {height}")
print()
print("Only this Vivado window region will be recorded.")
print("Other monitors are OUTSIDE the capture.")
print("========================================")

bus = dbus.SessionBus()

obj = bus.get_object(
    "org.gnome.Shell.Screencast",
    "/org/gnome/Shell/Screencast"
)

sc = dbus.Interface(
    obj,
    "org.gnome.Shell.Screencast"
)

options = dbus.Dictionary(
    {
        "draw-cursor": dbus.Boolean(True),
        "framerate": dbus.Int32(30)
    },
    signature="sv"
)

# Make the cursor very obvious during engineering recordings.
old_cursor_size = subprocess.run(
    ["gsettings", "get", "org.gnome.desktop.interface", "cursor-size"],
    text=True, capture_output=True
).stdout.strip()

subprocess.run([
    "gsettings", "set",
    "org.gnome.desktop.interface",
    "cursor-size", "36"
], check=False)

ok, actual = sc.ScreencastArea(
    x,
    y,
    width,
    height,
    str(raw),
    options
)

if not ok:
    sys.exit("ERROR: GNOME refused to start area recording.")

# Bring Vivado forward and put the pointer visibly inside the window.
subprocess.run(["xdotool", "windowactivate", wid], check=False)
time.sleep(0.5)

subprocess.run([
    "xdotool", "mousemove",
    "--window", wid,
    str(width // 2),
    str(height // 2)
], check=False)

# Tiny movement also forces GNOME/XWayland to redraw the pointer.
subprocess.run([
    "xdotool", "mousemove_relative", "--sync", "2", "2"
], check=False)

print()
print("========================================")
print(" RECORDING NOW — VIVADO ONLY")
print("========================================")
print("Perform the ILA test in Vivado.")
print("Leave the final waveform visible ~5 sec.")
print("Then return here and press ENTER.")
print("========================================")

try:
    input()
finally:
    sc.StopScreencast()

    if old_cursor_size:
        subprocess.run([
            "gsettings", "set",
            "org.gnome.desktop.interface",
            "cursor-size",
            old_cursor_size
        ], check=False)

time.sleep(2)

source = Path(str(actual))

if not source.exists():
    source = raw

if not source.exists():
    sys.exit("ERROR: Screencast file was not created.")

print("\nCompressing recording for GitHub portfolio...")

# Standard portfolio compression:
# - maximum 1280 px width
# - 15 fps
# - H.264
# - CRF 28
# - even dimensions for yuv420p compatibility
run([
    "ffmpeg", "-y",
    "-i", str(source),
    "-an",
    "-vf",
    "scale='min(1280,iw)':-2,fps=15,"
    "pad=ceil(iw/2)*2:ceil(ih/2)*2",
    "-c:v", "libx264",
    "-preset", "medium",
    "-crf", "28",
    "-pix_fmt", "yuv420p",
    "-movflags", "+faststart",
    str(mp4)
])

if not mp4.exists() or mp4.stat().st_size == 0:
    sys.exit("ERROR: MP4 compression failed.")

probe = run([
    "ffprobe",
    "-v", "error",
    "-show_entries",
    "format=duration,size:stream=codec_name,width,height,r_frame_rate",
    "-of", "default=noprint_wrappers=1",
    str(mp4)
], True)

print("\n===== COMPRESSED VIDEO VALIDATION =====")
print(probe.stdout)

size_mb = mp4.stat().st_size / (1024 * 1024)
print(f"Compressed size: {size_mb:.2f} MB")

# Portfolio policy: never automatically push oversized evidence.
MAX_UPLOAD_MB = 20

if size_mb > MAX_UPLOAD_MB:
    print(
        f"\nVideo is still {size_mb:.2f} MB. "
        "Applying stronger compression..."
    )

    smaller = mp4.with_name(mp4.stem + "_compressed.mp4")

    run([
        "ffmpeg", "-y",
        "-i", str(mp4),
        "-an",
        "-vf",
        "scale='min(960,iw)':-2,fps=12,"
        "pad=ceil(iw/2)*2:ceil(ih/2)*2",
        "-c:v", "libx264",
        "-preset", "medium",
        "-crf", "31",
        "-pix_fmt", "yuv420p",
        "-movflags", "+faststart",
        str(smaller)
    ])

    if not smaller.exists() or smaller.stat().st_size == 0:
        sys.exit("ERROR: Secondary compression failed.")

    smaller.replace(mp4)
    size_mb = mp4.stat().st_size / (1024 * 1024)

    print(f"Recompressed size: {size_mb:.2f} MB")

if size_mb > MAX_UPLOAD_MB:
    sys.exit(
        f"ERROR: Final video is {size_mb:.2f} MB. "
        "GitHub upload blocked by portfolio size policy."
    )

print(f"Compression gate: PASS ({size_mb:.2f} MB <= {MAX_UPLOAD_MB} MB)")

# Remove raw recording only after successful compression.
if source.exists() and source != mp4:
    source.unlink()

rel = mp4.relative_to(REPO)

branch = run(
    ["git", "branch", "--show-current"],
    True
).stdout.strip()

print("\n===== GITHUB =====")

run(["git", "add", "--", str(rel)])

run([
    "git", "commit",
    "-m", f"docs(zcu104): add ILA hardware capture {stamp}",
    "--", str(rel)
])

run(["git", "push", "origin", branch])

local = run(["git", "rev-parse", "HEAD"], True).stdout.strip()

remote_line = run(
    ["git", "ls-remote", "origin", f"refs/heads/{branch}"],
    True
).stdout.strip()

remote = remote_line.split()[0] if remote_line else ""

if local != remote:
    sys.exit("ERROR: GitHub SHA verification failed.")

print()
print("========================================")
print(" SUCCESS")
print(" Vivado-only capture : PASS")
print(" MP4 validation      : PASS")
print(" Git commit          : PASS")
print(" GitHub push         : PASS")
print(" Remote verification : PASS")
print(f" File: {rel}")
print("========================================")
