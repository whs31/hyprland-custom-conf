-- This file will not be overwritten across dots-hyprland updates.
-- Local workspace keybind overrides.

-- Replace SUPER+ALT+number with SUPER+SHIFT+number.
-- follow=true switches to the target workspace after moving the active window.
for i = 1, 10 do
    local key = i % 10
    hl.unbind("SUPER + ALT + " .. key)
    hl.bind("SUPER + SHIFT + " .. key, function()
        hl.dispatch(hl.dsp.window.move({ workspace = workspace_in_group(i), follow = true }))
    end, { description = "Window: Send to and follow workspace " .. i })
end

-- Keep the keypad bindings consistent with the number-row bindings.
local numpadkey = { 87, 88, 89, 83, 84, 85, 79, 80, 81, 90 }
for i = 1, 10 do
    hl.unbind("SUPER + ALT + code:" .. numpadkey[i])
    hl.bind("SUPER + SHIFT + code:" .. numpadkey[i], function()
        hl.dispatch(hl.dsp.window.move({ workspace = workspace_in_group(i), follow = true }))
    end)
end

hl.unbind("SUPER + L")
hl.bind(
    "SUPER + L",
    hl.dsp.exec_cmd("qs -c $qsConfig ipc call lock activate || hyprlock"),
    { description = "Session: Lock" }
)

hl.bind(
    "SUPER + U",
    hl.dsp.exec_cmd("qs -p $HOME/.config/hypr/custom/ai-usage ipc call aiUsage toggle"),
    { description = "Shell: Toggle Claude and Codex usage" }
)
