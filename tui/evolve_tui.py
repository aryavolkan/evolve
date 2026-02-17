#!/usr/bin/env python3
"""
Evolve TUI — terminal UI that mirrors the in-game arena GUI.

Reads  ~/.local/share/godot/app_userdata/Evolve/arena_states.json  (written by Godot)
Writes ~/.local/share/godot/app_userdata/Evolve/tui_commands.json  (read by Godot)

Run: python3 ~/evolve/tui/evolve_tui.py
"""

import json
import time
from datetime import datetime
from pathlib import Path

from textual.app import App, ComposeResult
from textual.binding import Binding
from textual.containers import Horizontal, Vertical
from textual.widgets import DataTable, Footer, Header, RichLog, Static
from rich.text import Text

# ── paths ────────────────────────────────────────────────────────────────────
GODOT_USER = Path.home() / ".local/share/godot/app_userdata/Evolve"
ARENA_STATES = GODOT_USER / "arena_states.json"
TUI_COMMANDS = GODOT_USER / "tui_commands.json"

POLL_INTERVAL = 0.5   # seconds between state refreshes
SPARKLINE_BARS = "▁▂▃▄▅▆▇█"


# ── helpers ──────────────────────────────────────────────────────────────────

def sparkline(values: list[float], width: int = 20) -> str:
    if not values:
        return "─" * width
    mn, mx = min(values), max(values)
    rng = mx - mn or 1.0
    bars = SPARKLINE_BARS
    result = ""
    for v in values[-width:]:
        idx = int((v - mn) / rng * (len(bars) - 1))
        result += bars[idx]
    return result.ljust(width, "─")


def fmt_score(v: float) -> str:
    return f"{int(v):,}"


def send_command(action: str, **kwargs) -> None:
    cmd = {"action": action, **kwargs}
    TUI_COMMANDS.write_text(json.dumps(cmd))


def load_state() -> dict | None:
    try:
        text = ARENA_STATES.read_text()
        return json.loads(text)
    except Exception:
        return None


# ── widgets ──────────────────────────────────────────────────────────────────

class HeaderBar(Static):
    """Single-line status bar at the top."""

    DEFAULT_CSS = """
    HeaderBar {
        height: 1;
        background: $primary-darken-2;
        color: $text;
        padding: 0 1;
    }
    """

    def update_state(self, state: dict | None) -> None:
        if state is None:
            self.update("[dim]◌  Waiting for Godot...[/]")
            return
        mode    = state.get("mode", "?")
        gen     = state.get("generation", 0)
        best    = fmt_score(state.get("all_time_best", 0))
        speed   = state.get("time_scale", 1.0)
        stage   = state.get("curriculum_label", "")
        ts      = datetime.now().strftime("%H:%M:%S")
        self.update(
            f"[bold cyan]EVOLVE[/]  "
            f"[yellow]{mode}[/]  "
            f"Gen:[bold]{gen}[/]  "
            f"Best:[bold green]{best}[/]  "
            f"Speed:[bold]{speed:.0f}×[/]  "
            f"[dim]{stage}[/]  "
            f"[dim]{ts}[/]"
        )


class StatsPanel(Static):
    """Right-side stats + sparkline panel."""

    DEFAULT_CSS = """
    StatsPanel {
        width: 36;
        padding: 1 2;
        background: $surface;
        border: round $primary-darken-2;
    }
    """

    def update_state(self, state: dict | None) -> None:
        if state is None:
            self.update("[dim]no data[/]")
            return

        pop      = state.get("population_size", 0)
        avg      = fmt_score(state.get("avg_fitness", 0))
        mn       = fmt_score(state.get("min_fitness", 0))
        stag     = state.get("generations_without_improvement", 0)
        neat     = state.get("use_neat", False)
        spc      = state.get("neat_species_count", 0)
        h_best   = state.get("history_best", [])
        h_avg    = state.get("history_avg", [])

        spark_best = sparkline(h_best, 22)
        spark_avg  = sparkline(h_avg, 22)

        neat_line = f"  Species: [cyan]{spc}[/]" if neat else "  Mode: [cyan]Standard[/]"

        lines = [
            f"[bold]Population[/]  [cyan]{pop}[/]",
            f"  Avg:  [green]{avg}[/]",
            f"  Min:  [dim]{mn}[/]",
            f"  Stag: [yellow]{stag}[/] gen",
            neat_line,
            "",
            "[bold]Best fitness[/]",
            f"  [green]{spark_best}[/]",
            "[bold]Avg fitness[/]",
            f"  [yellow]{spark_avg}[/]",
        ]
        self.update("\n".join(lines))


# ── main app ─────────────────────────────────────────────────────────────────

class EvolveTUI(App):
    """Terminal UI for Evolve neuroevolution game."""

    TITLE = "Evolve TUI"
    SUB_TITLE = "arena monitor"

    CSS = """
    Screen {
        background: $background;
    }

    #body {
        height: 1fr;
    }

    #arenas {
        width: 1fr;
        border: round $primary-darken-2;
    }

    #log-panel {
        height: 10;
        border: round $primary-darken-2;
        padding: 0 1;
    }

    RichLog {
        height: 1fr;
    }
    """

    BINDINGS = [
        Binding("t", "cmd_train",      "Train",    show=True),
        Binding("p", "cmd_play",       "Play best",show=True),
        Binding("equal", "cmd_speed_up",   "Speed+",   show=True),
        Binding("minus", "cmd_speed_down", "Speed-",   show=True),
        Binding("f", "cmd_focus",      "Focus",    show=True),
        Binding("escape", "cmd_unfocus","Unfocus",  show=True),
        Binding("q", "quit",           "Quit",     show=True),
    ]

    def __init__(self):
        super().__init__()
        self._state: dict | None = None
        self._focus_idx: int = 0

    def compose(self) -> ComposeResult:
        yield HeaderBar(id="header-bar")
        with Horizontal(id="body"):
            with Vertical(id="arenas"):
                yield DataTable(id="arena-table", zebra_stripes=True, cursor_type="row")
            yield StatsPanel(id="stats")
        with Vertical(id="log-panel"):
            yield RichLog(id="log", highlight=True, markup=True, wrap=False)
        yield Footer()

    def on_mount(self) -> None:
        # Set up arena table columns
        table: DataTable = self.query_one("#arena-table", DataTable)
        table.add_columns("Arena", "Ind", "Score", "Status", "Time")
        # Start polling
        self.set_interval(POLL_INTERVAL, self._poll)

    def _poll(self) -> None:
        new_state = load_state()
        self._state = new_state
        self._refresh_ui()

    def _refresh_ui(self) -> None:
        state = self._state

        # Header
        self.query_one("#header-bar", HeaderBar).update_state(state)

        # Stats
        self.query_one("#stats", StatsPanel).update_state(state)

        # Arena table
        table: DataTable = self.query_one("#arena-table", DataTable)
        table.clear()
        if state:
            arenas = sorted(
                state.get("arenas", []),
                key=lambda a: a.get("score", 0),
                reverse=True,
            )
            for a in arenas:
                aid       = a.get("id", 0)
                ind       = a.get("individual", -1)
                score     = a.get("score", 0.0)
                done      = a.get("done", False)
                alive     = a.get("alive", False)
                elapsed   = a.get("time", 0.0)

                label = f"A{aid+1:02d}"

                if done:
                    status = Text("○ DONE", style="dim")
                elif not alive:
                    status = Text("✗ DEAD", style="red")
                else:
                    status = Text("● ALIVE", style="green")

                score_txt = Text(fmt_score(score), style="bold" if not done else "dim")
                time_txt  = f"{elapsed:.0f}s"

                table.add_row(label, str(ind), score_txt, status, time_txt)

        # Log
        log: RichLog = self.query_one("#log", RichLog)
        if state:
            entries = state.get("log", [])
            # Only write new entries (track by count — simple approach)
            for entry in entries[-8:]:
                ts  = datetime.fromtimestamp(entry.get("ts", 0)).strftime("%H:%M:%S")
                msg = entry.get("msg", "")
                log.write(f"[dim]{ts}[/]  {msg}")

    # ── actions ──────────────────────────────────────────────────────────────

    def action_cmd_train(self) -> None:
        send_command("start_training")
        self._log_local("→ start_training sent")

    def action_cmd_play(self) -> None:
        send_command("play_best")
        self._log_local("→ play_best sent")

    def action_cmd_speed_up(self) -> None:
        send_command("speed_up")
        self._log_local("→ speed_up sent")

    def action_cmd_speed_down(self) -> None:
        send_command("speed_down")
        self._log_local("→ speed_down sent")

    def action_cmd_focus(self) -> None:
        state = self._state
        if state:
            arenas = state.get("arenas", [])
            if arenas:
                self._focus_idx = (self._focus_idx + 1) % len(arenas)
                idx = arenas[self._focus_idx].get("id", 0)
                send_command("focus_arena", index=idx)
                self._log_local(f"→ focus arena {idx}")

    def action_cmd_unfocus(self) -> None:
        send_command("exit_focus")
        self._log_local("→ exit_focus sent")

    def _log_local(self, msg: str) -> None:
        log: RichLog = self.query_one("#log", RichLog)
        ts = datetime.now().strftime("%H:%M:%S")
        log.write(f"[dim]{ts}[/]  [italic cyan]{msg}[/]")


if __name__ == "__main__":
    app = EvolveTUI()
    app.run()
