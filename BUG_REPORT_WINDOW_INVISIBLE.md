# Bug Report: Window Invisibility Issue

**Date**: 2026-02-15  
**Severity**: P0 - Critical Blocker  
**Platform**: Linux Mint (Cinnamon Desktop) with NVIDIA RTX 5070  
**Godot Version**: 4.5-stable  

## Summary

Godot windows fail to render/composite correctly on Cinnamon desktop environment, making the game completely unusable in GUI mode despite the application running correctly.

## Environment

- **OS**: Linux 6.17.0-14-generic (x64)
- **Desktop**: Cinnamon (window manager + compositor)
- **GPU**: NVIDIA GeForce RTX 5070
- **Driver**: NVIDIA 590.48.01
- **Display**: Dual 2560x1440 monitors (DP-2 primary at 0,0 | DP-0 at 2560,233)
- **Godot**: 4.5-stable (official build)

## Reproduction Steps

1. Launch Godot editor:
   ```bash
   DISPLAY=:0 /usr/local/bin/godot --path . project.godot
   ```

2. OR launch game directly:
   ```bash
   DISPLAY=:0 /usr/local/bin/godot --path . res://main.tscn
   ```

3. **Expected**: Window appears on screen
4. **Actual**: No window visible despite process running successfully

## Technical Analysis

### Window Properties (Confirmed Working)

```bash
$ xwininfo -id 83886084
Window id: 0x5000004 "Evolve (DEBUG)"
  Position: 640x340 (within primary display bounds)
  Size: 1280x720
  Map State: IsViewable ✓
  Depth: 24-bit TrueColor
  Override Redirect: No
```

### Stacking Order (Confirmed Correct)

```bash
$ xprop -root _NET_CLIENT_LIST_STACKING
...0x5000004  # Godot window is TOP of stack
```

### Window Manager State

```bash
$ xprop -id 83886084 _NET_WM_STATE
_NET_WM_STATE_FOCUSED  # Window is focused
```

### The Bug

**Mouse position test reveals the issue:**

```bash
$ xdotool mousemove 640 340 getmouselocation
x:640 y:340 screen:0 window:0  # Reports root window, NOT Godot window!
```

Despite Godot window being:
- ✓ At the top of the stacking order
- ✓ Marked as visible (IsViewable)
- ✓ Focused by window manager
- ✓ Within screen bounds
- ✓ Rendering correctly (framebuffer capture succeeds)

**The compositor does not paint it.**

## Framebuffer Evidence

Direct window capture proves the game is rendering correctly:

```bash
$ import -window 83886084 /tmp/window.png
# Successfully captures the title screen menu
```

The captured image shows:
- Title: "EVOLVE - Neuroevolution Arcade Survival"
- Full menu with 8 options (PLAY, WATCH AI, TRAIN AI, etc.)
- Proper rendering, no visual glitches

## Rendering Backends Tested

### Vulkan (default)
```
Vulkan 1.4.325 - Forward+ - NVIDIA GeForce RTX 5070
Result: Window invisible
```

### OpenGL3 (tested workaround)
```bash
godot --rendering-driver opengl3 ...
OpenGL API 3.3.0 NVIDIA 590.48.01 - NVIDIA GeForce RTX 5070
Result: Window still invisible
```

**Conclusion**: Issue affects both Vulkan AND OpenGL3, indicating a compositor-level problem.

## Root Cause Hypothesis

**Cinnamon compositor fails to composite Godot 4.5 windows**

Possible causes:
1. Godot 4.5 uses direct scanout / compositor bypass
2. Missing EWMH hints that Cinnamon requires
3. Incompatibility with Godot's Vulkan/OpenGL swapchain presentation
4. Z-order compositor bug specific to Godot window types
5. NVIDIA driver + Cinnamon interaction issue

## Impact

- **User Experience**: Game is completely unusable in GUI mode
- **Development**: Cannot use Godot editor visually
- **Workaround Available**: Headless mode works perfectly (10 workers running successfully)

## Workaround

The game works perfectly in headless mode:

```bash
godot --headless --rendering-driver dummy --path . -- --auto-train
```

All 10 workers successfully train using this method.

## Additional Notes

- Window manager commands work (focus, raise, etc.)
- Window receives keyboard input (may not process it due to no painting)
- No errors in Xorg logs
- No errors in Godot logs (renders normally)
- Issue reproducible 100% of the time

## Recommended Actions

1. **Short-term**: Document headless-only limitation for Cinnamon users
2. **Medium-term**: Test on other desktop environments (GNOME, KDE, XFCE)
3. **Long-term**: File upstream bug reports:
   - Godot Engine (window manager compatibility)
   - Cinnamon (compositor behavior with modern Godot)
   - NVIDIA (if driver-specific)

## Test Checklist for Future Debugging

- [ ] Test on GNOME Shell
- [ ] Test on KDE Plasma
- [ ] Test on XFCE
- [ ] Test with Mesa/Intel graphics
- [ ] Test with AMD graphics
- [ ] Test Godot 4.4 vs 4.5
- [ ] Test with compositor disabled
- [ ] Test with older NVIDIA driver
- [ ] Check Godot display server settings
- [ ] Try X11 vs Wayland session

---

**Investigator**: Charles (OpenClaw Assistant)  
**Investigation Time**: ~15 minutes of systematic debugging  
**Tools Used**: xwininfo, xprop, xdotool, wmctrl, import, xrandr
