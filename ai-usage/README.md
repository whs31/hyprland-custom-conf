# Claude + Codex usage widget

Native Quickshell widget for the end4/dots-hyprland setup. It uses the
[CodexBar](https://github.com/steipete/CodexBar) Linux CLI as its data source,
but all shell integration lives in this portable `custom` repository.

## Dependency

On Arch Linux:

```bash
yay -S codexbar-cli
```

Claude Code and Codex must already be installed and authenticated. If Claude
shows an expired-session message, run:

```bash
claude login
```

## Controls

- Click the compact widget to open details; click outside or press `Esc` to close.
- Right-click the compact widget (or press `R` in the details) to refresh.
- `Super+U` toggles details, starting the widget right away if it isn't running yet.
- Data refreshes every five minutes. The tick on each bar marks where usage
  would be if it were spread evenly across the window.

## Startup

`launch.sh` is started from `execs.lua`. On a fresh boot it waits until the
system has been up for five minutes before starting the widget; after that
(e.g. restarting Hyprland) it starts immediately. Override the delay with
`AI_USAGE_BOOT_DELAY=<seconds>`.

The compact widget and the end4 bar share the Top layer, where the most recently
mapped surface is drawn on top. The widget listens for Hyprland `openlayer`
events and remaps itself whenever `quickshell:bar` appears (startup, unlock,
shell reload), so it always stays above the bar.

The compact widget is positioned next to the centred end4 controls. If a
different monitor or bar layout needs adjustment, change only
`compactBarOffsetFromCenter` near the top of `shell.qml`.

For a manual start or a QML error check:

```bash
qs -n -p ~/.config/hypr/custom/ai-usage
```
