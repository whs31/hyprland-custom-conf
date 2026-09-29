-- This file will not be overwritten across dots-hyprland updates.
-- The file name is for the sake of organization and does not matter
-- See the corresponding files in ~/.config/hypr/hyprland for examples

hl.on("hyprland.start", function()
    hl.exec_cmd("qs -n -p $HOME/.config/hypr/custom/ai-usage")
end)
