# Evolve TUI

Terminal UI that mirrors the in-game arena training GUI — monitor all parallel arenas, fitness history, and send control commands without touching the game window.

## Run

```bash
python3 ~/evolve/tui/evolve_tui.py
```

Requires `textual` and `rich`:
```bash
pip3 install textual rich --break-system-packages
```

## How it works

| Direction | File | Description |
|---|---|---|
| Godot → TUI | `arena_states.json` | Written every 0.5s by `tui_bridge.gd` |
| TUI → Godot | `tui_commands.json` | Written on keypress, polled each frame by Godot |

Both files live in `~/.local/share/godot/app_userdata/Evolve/`.

## Layout

```
┌─ status bar: mode │ gen │ best │ speed │ curriculum ────────────┐
├─ arena table ──────────────────────┬─ stats + sparklines ───────┤
│ A01  ind:5  189,512  ● ALIVE  12s  │  Population: 120           │
│ A02  ind:8       0   ○ DONE    0s  │  Avg: 143,847              │
│ ...                                │  ▁▂▄▅▇▇▇██ (best)          │
├────────────────────────────────────┴───────────────────────────┤
│ log: 00:21:03  gen 47 → best 189,512                           │
├────────────────────────────────────────────────────────────────┤
│ [t]rain  [p]lay best  [=]speed+  [-]speed-  [f]ocus  [q]uit   │
└────────────────────────────────────────────────────────────────┘
```

## Key bindings

| Key | Action |
|-----|--------|
| `t` | Start training |
| `p` | Play best network |
| `=` / `+` | Speed up (×2, ×4 … ×16) |
| `-` | Speed down |
| `f` | Cycle focus to next arena (fullscreen in-game) |
| `Esc` | Exit fullscreen |
| `q` | Quit TUI |

The TUI works whether Godot is running headless or windowed. If no game is running, it shows "Waiting for Godot…"
