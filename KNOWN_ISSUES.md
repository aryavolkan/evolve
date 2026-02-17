# Known Issues

## ❌ Godot Window Invisible on Linux Mint / Cinnamon

**Status:** Unfixed  
**Date:** 2026-02-15  
**Platform:** Linux Mint (Cinnamon) + NVIDIA RTX 5070 + Godot 4.5  
**Severity:** P2 — GUI mode only; headless training unaffected

### Symptom

Godot windows fail to render/composite on Cinnamon desktop. The application runs correctly (game logic works, headless training works) but the window is invisible in GUI mode.

### Root Cause

Fundamental incompatibility between Godot 4.5's rendering pipeline and Cinnamon's compositor, likely exacerbated by NVIDIA driver interactions.

### Attempted Fixes (all failed)

1. `--rendering-driver opengl3` — no change
2. `--rendering-driver vulkan` — no change  
3. Window always-on-top hints — no change
4. `DISPLAY=:0` explicit — no change
5. Mutter compositor disable — broke desktop
6. Xvfb virtual display — game invisible in Xvfb
7. Xvfb + x11vnc passthrough — VNC showed blank window
8. `xdotool windowraise` + focus forcing — no change

### Workaround

Use **headless mode** for all training (already default):
```bash
godot --headless --rendering-driver dummy -- --auto-train
```

GUI mode works on macOS and Windows. Sandbox/playback modes intended for non-Cinnamon Linux or other platforms.

---

## ✅ NEAT + NSGA2 Incompatibility (Fixed)

**Fixed:** 2026-02-16 (commit `8143fa1`)  
**Symptom:** Workers silently hung at gen boundary when `use_neat=true` + `use_nsga2=true`  
**Cause:** `NeatEvolution` has no `set_objectives()` — only `set_fitness()`. Code called `set_objectives()` unconditionally when `use_nsga2=true`, causing a silent Godot script error.  
**Fix:** Guard in `standard_training_mode.gd` forces `use_nsga2=false` when `use_neat=true`.

---

## ✅ NEAT SubViewport Deadlock (Fixed)

**Fixed:** 2026-02-16 (commit `6234c4c`)  
**Symptom:** NEAT workers hung at 0% CPU after 8–30 generations, no error output  
**Cause:** `thread_model=2` (MultiThreaded rendering) caused SubViewport deadlock in NEAT's per-individual topology evaluation  
**Fix:** Set `thread_model=0` in `project.godot`; added batch-processor bypass for NEAT (each individual has unique topology)

---

## ✅ Early Stop Orphaned Games (Fixed)

**Fixed:** 2026-02-16 (commit `b525feb`)  
**Symptom:** Workers froze at 0% CPU after early-stop trigger  
**Cause:** `_start_next_batch()` called after early-stop fired, launching orphaned SubViewport games that ran forever  
**Fix:** Added `training_complete` check before `_start_next_batch()` and `return` after early-stop in `_on_generation_complete`

---

## ✅ Worker 30-Minute Death (Fixed)

**Fixed:** 2026-02-13  
**Symptom:** All workers died after exactly 30 minutes  
**Cause:** `nohup bash -c "python ..."` wrapper caused premature subprocess exit  
**Fix:** Use direct invocation: `nohup python overnight_evolve.py ...`
