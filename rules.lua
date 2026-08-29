-- This file will not be overwritten across dots-hyprland updates.
-- Local window rules.

-- Float Radar MMS / Corona windows by default when their class contains
-- radar_mms, radar-mms, or corona.
hl.window_rule({
    match = { class = ".*(radar_mms|radar-mms|corona).*" },
    float = true
})
