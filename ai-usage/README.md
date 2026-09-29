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

- Click the compact widget to open details.
- Right-click the compact widget to refresh.
- `Super+U` toggles details.
- Data refreshes every five minutes.

The compact widget is positioned next to the centred end4 controls. If a
different monitor or bar layout needs adjustment, change only
`compactBarOffsetFromCenter` near the top of `shell.qml`.

For a manual start or a QML error check:

```bash
qs -n -p ~/.config/hypr/custom/ai-usage
```
