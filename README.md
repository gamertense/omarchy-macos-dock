# omarchy-macos-dock

A macOS-style dock for [Omarchy](https://omarchy.org/), as an Omarchy shell
plugin.

![The dock, magnified over Telegram](preview.png)

One frosted bar of pinned apps, then running apps, a divider, Downloads and
Trash. Icons magnify under the pointer, running apps get a dot, and hovering
shows the app's name.

- Click a closed app to launch it (it bounces), a running one to bring back
  its last window, including one moved to the `special:scratchpad` workspace.
  Click the app in front again to cycle its windows.
- Drag an icon along the dock to reorder it (a running app gets kept in the
  dock where you drop it); drag a kept app up off the dock to remove it.
- Right-click for New Window, Keep in / Remove from Dock, and Quit; on Trash,
  Empty Trash.
- Pins live in `~/.config/omarchy/jack-dock.json` as desktop-file ids:
  `{ "pinned": ["brave-browser", "foot"] }`.
- The dock reserves its height, so tiled windows stop above it.

## Install

```bash
omarchy plugin add https://github.com/gamertense/omarchy-macos-dock.git --enable
omarchy restart shell
```

For the blur behind the bar, add this to `~/.config/hypr/bindings.lua` (or any
Hyprland config file):

```lua
hl.layer_rule({ match = { namespace = "jack-dock" }, blur = true, ignore_alpha = 0.1 })
```

Turn off any other dock plugin first, or you'll get two.

## Develop

```bash
node test.js                 # layout and magnification check
omarchy restart shell        # after editing the QML
```

Launching uses `uwsm-app` and `gtk-launch`; Downloads and Trash open in Nautilus.
All ship with Omarchy.
