-- This file will not be overwritten across dots-hyprland updates.
-- Local window rules.

-- Float Radar MMS / Corona windows by default when their class contains
-- radar_mms, radar-mms, or corona.
hl.window_rule({
    match = { class = ".*(radar_mms|radar-mms|corona).*" },
    float = true
})

-- AI usage widget: its cards are opaque, so skip end4's quickshell:.* blur.
-- That blur uses ignore_alpha = 0.79, which cuts through the anti-aliased
-- rounded corners and makes them look fuzzy.
hl.layer_rule({ match = { namespace = "quickshell:aiUsage.*" }, blur = false })
hl.layer_rule({ match = { namespace = "quickshell:aiUsage.*" }, xray = false })
hl.layer_rule({ match = { namespace = "quickshell:aiUsage.*" }, ignore_alpha = 1 })
