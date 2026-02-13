#!/usr/bin/env python3
"""Export a trained Evolve AI model as a standalone .pck demo.

Packages best_network.nn into the Godot project so it can be played with:
    godot --main-pack evolve_demo.pck -- --demo

Usage:
    python scripts/export_demo.py
    python scripts/export_demo.py --output my_demo.pck
    python scripts/export_demo.py --network /path/to/best_network.nn
"""

import argparse
import os
import platform
import shutil
import subprocess
import sys


def get_user_data_dir() -> str:
    """Return Godot's user:// data directory for this project."""
    system = platform.system()
    if system == "Linux":
        base = os.environ.get(
            "XDG_DATA_HOME", os.path.expanduser("~/.local/share")
        )
        return os.path.join(base, "godot", "app_userdata", "Evolve")
    elif system == "Darwin":
        return os.path.expanduser(
            "~/Library/Application Support/Godot/app_userdata/Evolve"
        )
    elif system == "Windows":
        return os.path.join(
            os.environ.get("APPDATA", ""), "Godot", "app_userdata", "Evolve"
        )
    else:
        sys.exit(f"Unsupported platform: {system}")


def find_godot() -> str:
    """Find the Godot executable on PATH."""
    for name in ("godot", "godot4"):
        path = shutil.which(name)
        if path:
            return path
    sys.exit(
        "Error: Godot executable not found on PATH. "
        "Install Godot 4.5+ and ensure 'godot' is in your PATH."
    )


def ensure_export_presets(project_dir: str) -> bool:
    """Generate a minimal export_presets.cfg if one doesn't exist.

    Returns True if we created the file (so we know to clean it up).
    """
    presets_path = os.path.join(project_dir, "export_presets.cfg")
    if os.path.exists(presets_path):
        return False

    # Minimal preset for PCK-only export (platform doesn't matter for .pck)
    content = """\
[preset.0]

name="PCK"
platform="Linux"
runnable=true
dedicated_server=false
custom_features=""
export_filter="all_resources"
include_filter=""
exclude_filter=""
export_path=""
patches=[]
script_export_mode=2

[preset.0.options]
"""
    with open(presets_path, "w") as f:
        f.write(content)
    print(f"Created temporary {presets_path}")
    return True


def main():
    parser = argparse.ArgumentParser(
        description="Export trained Evolve AI as a standalone .pck demo"
    )
    parser.add_argument(
        "--output", "-o",
        default="evolve_demo.pck",
        help="Output .pck filename (default: evolve_demo.pck)",
    )
    parser.add_argument(
        "--network", "-n",
        default=None,
        help="Path to best_network.nn (default: auto-detect from Godot user data)",
    )
    args = parser.parse_args()

    project_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

    # 1. Locate the trained network
    network_path = args.network
    if not network_path:
        network_path = os.path.join(get_user_data_dir(), "best_network.nn")

    if not os.path.exists(network_path):
        sys.exit(
            f"Error: Network file not found at {network_path}\n"
            "Train a model first (press T in-game) or specify --network."
        )

    print(f"Using network: {network_path}")

    # 2. Copy network into res://models/ so it gets packed into the .pck
    models_dir = os.path.join(project_dir, "models")
    os.makedirs(models_dir, exist_ok=True)
    dest = os.path.join(models_dir, "best_network.nn")
    shutil.copy2(network_path, dest)
    print(f"Copied network to {dest}")

    # 3. Ensure export presets exist
    created_presets = ensure_export_presets(project_dir)

    # 4. Run Godot export
    godot = find_godot()
    output_path = os.path.abspath(args.output)
    cmd = [godot, "--headless", "--path", project_dir, "--export-pack", "PCK", output_path]
    print(f"Running: {' '.join(cmd)}")

    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
        if result.returncode != 0:
            print(f"Godot stderr:\n{result.stderr}")
            sys.exit(f"Export failed with return code {result.returncode}")
    except subprocess.TimeoutExpired:
        sys.exit("Export timed out after 120 seconds")

    # 5. Clean up
    shutil.rmtree(models_dir)
    print(f"Cleaned up {models_dir}/")

    if created_presets:
        os.remove(os.path.join(project_dir, "export_presets.cfg"))
        print("Cleaned up temporary export_presets.cfg")

    if os.path.exists(output_path):
        size_mb = os.path.getsize(output_path) / (1024 * 1024)
        print(f"\nSuccess! Created {output_path} ({size_mb:.1f} MB)")
        print(f"Run with: godot --main-pack {args.output} -- --demo")
    else:
        sys.exit("Export completed but output file not found.")


if __name__ == "__main__":
    main()
