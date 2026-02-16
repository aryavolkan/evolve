# Window Visibility Bug - Fix Attempts & Solutions

**Status**: ❌ **UNFIXED** - All attempted solutions failed  
**Date**: 2026-02-15  
**System**: Linux Mint + Cinnamon + NVIDIA RTX 5070 + Godot 4.5

## Summary

After extensive debugging and 8 different fix attempts, the window visibility bug persists. The issue appears to be a **fundamental incompatibility between Godot 4.5's rendering pipeline and the Linux Mint Cinnamon desktop environment**, possibly exacerbated by NVIDIA driver/compositor interactions.

---

## Attempted Fixes

### ❌ Fix #1: Fullscreen Mode
**Approach**: Launch with `--fullscreen` flag  
**Result**: FAILED - Window still invisible  
**Command**: `godot --path . res://main.tscn -- --fullscreen`

### ❌ Fix #2: OpenGL3 Renderer (vs Vulkan)
**Approach**: Force OpenGL3 instead of default Vulkan  
**Result**: FAILED - Same issue with both renderers  
**Command**: `godot --rendering-driver opengl3 --path . res://main.tscn`  
**Note**: Proves this is NOT a Vulkan-specific issue

### ❌ Fix #3: Disable Cinnamon Compositor
**Approach**: Disable Muffin compositor entirely  
**Result**: FAILED - Window still invisible even without compositor  
**Commands**:
```bash
dbus-send --dest=org.Cinnamon.Muffin /org/Cinnamon/Muffin \
  org.Cinnamon.Muffin.DisableCompositing
godot --path . res://main.tscn
```
**Significance**: This rules out compositor as sole cause

### ❌ Fix #4: Wayland Display Driver
**Approach**: Try Wayland instead of X11  
**Result**: FAILED - Wayland backend loaded but window still invisible  
**Command**: `godot --display-driver wayland --path . res://main.tscn`  
**Note**: Session is X11, so Wayland may have fallen back to XWayland

### ❌ Fix #5: Always-On-Top Window Mode
**Approach**: Modified `project.godot` with forced window properties:
```ini
[display]
window/size/always_on_top=true
window/size/borderless=false
window/size/resizable=true
window/vsync/vsync_mode=1
window/per_pixel_transparency/allowed=false
```
**Result**: FAILED - No effect on visibility

### ❌ Fix #6: Single Window Mode
**Approach**: Force single-window rendering  
**Command**: `godot --single-window --path . res://main.tscn`  
**Result**: FAILED - No improvement

### ❌ Fix #7: Force Window Mapping via xdotool
**Approach**: Programmatically force window visibility after launch:
```bash
xdotool windowmap $WINDOW_ID
xdotool windowactivate --sync $WINDOW_ID
xdotool windowraise $WINDOW_ID
xdotool windowfocus $WINDOW_ID
```
**Result**: FAILED - All commands succeeded but window remains invisible  
**Script**: `launch_force_visible.sh`  
**Note**: Window accepts all X11 commands but desktop refuses to paint it

### ❌ Fix #8: Borderless/Window Mode Variations
**Approach**: Tried combinations of:
- Borderless vs decorated windows
- Maximized vs normal size
- Different screen positions
**Result**: All FAILED

---

## Technical Analysis

### What We Confirmed

✅ **Window Exists Correctly**:
- Window ID: 0x5000004
- Size: 1280x720
- Position: Within screen bounds (640, 340)
- Map State: IsViewable
- Window Type: _NET_WM_WINDOW_TYPE_NORMAL

✅ **Z-Order Is Correct**:
- Window is at top of `_NET_CLIENT_LIST_STACKING`
- Has `_NET_WM_STATE_FOCUSED`
- No windows above it

✅ **Rendering Works**:
- `import -window 0x5000004 screenshot.png` successfully captures rendered content
- Game UI renders perfectly (title screen visible in capture)
- Both Vulkan and OpenGL3 render correctly

✅ **X11 Commands Work**:
- xdotool can find, focus, raise, and move the window
- Window accepts all window manager commands
- No errors in command execution

### What's Broken

❌ **Desktop Painting**:
- Desktop/compositor refuses to paint the window
- Screen shows only desktop background
- Mouse at window coordinates reports `window:0` (root) instead of Godot window
- Visual output pipeline is broken

❌ **Applies to ALL Display Methods**:
- X11 (default)
- Wayland
- With compositor enabled
- With compositor disabled
- Vulkan renderer
- OpenGL3 renderer

### Root Cause Hypothesis

The issue is likely one of these:

1. **NVIDIA Driver Bug**: RTX 5070 + driver 590.48.01 may have a scanout/presentation bug that affects Godot's specific rendering path
   
2. **Godot 4.5 Display Server Bug**: The X11 display server in Godot 4.5 may be using an unsupported presentation mode on this hardware/driver combo

3. **Cinnamon/Muffin Bug**: Some specific interaction between Godot's window creation and Cinnamon's window management

4. **Graphics Pipeline Mismatch**: Godot may be rendering to an off-screen buffer that never gets composited to the visible display

---

## Recommended Workarounds

### ✅ Workaround #1: Headless Mode (WORKS PERFECTLY)

**Status**: ✅ **CONFIRMED WORKING**  
**Use Case**: Training, automation, server deployments

```bash
godot --headless --rendering-driver dummy \
  --path . -- --auto-train --worker-id=$(uuidgen)
```

**Proof**: 10 workers successfully running for hours with this method

**Advantages**:
- 100% reliable
- No GPU overhead
- Perfect for ML training
- Can run unlimited instances

**Limitations**:
- No visual feedback
- Can't play the game interactively

---

### ✅ Workaround #2: Remote Desktop / VNC (UNTESTED)

**Approach**: Run on virtual X display and view via VNC

**Setup**:
```bash
# Install requirements
sudo apt-get install xvfb x11vnc

# Run script
./launch_vnc.sh
```

**Script** (`launch_vnc.sh`):
```bash
#!/bin/bash
Xvfb :99 -screen 0 1280x720x24 &
export DISPLAY=:99
x11vnc -display :99 -forever -shared &
godot --path . res://main.tscn
```

**Access**: VNC client → `localhost:5900`

**Status**: Created but not tested (tools not installed)

---

### ✅ Workaround #3: Different Desktop Environment

**Recommendation**: Test on GNOME or KDE

**Commands**:
```bash
# Install GNOME session
sudo apt-get install gnome-session

# Log out and select "GNOME" at login screen
# Then test Godot
```

**Rationale**: May not have the same compositor/rendering conflict

---

### ✅ Workaround #4: Downgrade to Godot 4.4

**Approach**: If regression from 4.4 → 4.5

**Commands**:
```bash
# Download Godot 4.4
wget https://github.com/godotengine/godot/releases/download/4.4-stable/Godot_v4.4-stable_linux.x86_64.zip
unzip Godot_v4.4-stable_linux.x86_64.zip
./Godot_v4.4-stable_linux.x86_64 --path . res://main.tscn
```

---

## Next Steps for Real Fix

1. **File Bug Reports**:
   - Godot Engine GitHub (with full reproduction case)
   - NVIDIA Developer Forums (driver team)
   - Linux Mint / Cinnamon bug tracker

2. **Test Matrix**:
   - [ ] Test on GNOME
   - [ ] Test on KDE Plasma
   - [ ] Test on XFCE (lightweight)
   - [ ] Test with Mesa/Intel integrated graphics
   - [ ] Test with AMD GPU
   - [ ] Test Godot 4.4 vs 4.5
   - [ ] Test on different NVIDIA driver versions
   - [ ] Test on Ubuntu (vs Mint)

3. **Upstream Investigation**:
   - Bisect Godot commits between 4.4 and 4.5
   - Enable Godot verbose logging for display server
   - Check if issue exists with other Vulkan/OpenGL apps
   - Test with different X11 visual depths

4. **Potential Code Fix**:
   - Modify Godot's X11 display server backend
   - Add compatibility flags for Cinnamon
   - Implement fallback rendering path
   - Add explicit window mapping calls

---

## Conclusion

After 8 different fix attempts and extensive debugging, **this bug cannot be fixed via configuration or command-line flags**. It requires either:

- Upstream fixes in Godot, NVIDIA drivers, or Cinnamon
- OR using the headless workaround (which works perfectly)
- OR switching desktop environments

**For now, use headless mode for all training/automation tasks.**

---

**Investigation Time**: ~45 minutes  
**Fix Attempts**: 8 different approaches  
**Success Rate**: 0/8 (headless mode excluded as not a "fix")  
**Recommended Action**: Use headless mode + file upstream bug reports
