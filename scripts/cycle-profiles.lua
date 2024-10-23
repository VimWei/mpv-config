-- cycle-profiles
-- src: https://github.com/VimWei/mpv-config

local profiles = {
    "autofit-max",
    "autofit-large",
    "autofit-normal",
    "autofit-small",
    "left-2/3",
    "right-2/3",
    "left-1/2",
    "right-1/2"
}

local current_profile = 0

function cycle_profiles(forward)
    if forward then
        current_profile = (current_profile % #profiles) + 1
    else
        current_profile = (current_profile - 1)
        if current_profile < 1 then
            current_profile = #profiles
        end
    end
    mp.command("apply-profile " .. profiles[current_profile])
end

mp.add_key_binding(nil, "cycle-profiles-forward", function() cycle_profiles(true) end)
mp.add_key_binding(nil, "cycle-profiles-backward", function() cycle_profiles(false) end)
