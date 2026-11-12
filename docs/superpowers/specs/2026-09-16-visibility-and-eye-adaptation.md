# Visibility, darkness and eye adaptation — notes

**Date:** 2026-09-16 · **Phase:** 10 (3D) · **Status:** design notes, tuned live in `scenes/test/camera_test_v5_manhattan.tscn`

## The scale
Visibility is a 0–100 number. 100 is perfect daylight; 0 is blind darkness.

| Situation | Visibility |
|---|---|
| Night, flashlight off, eyes not adapted | ~10 |
| Night, flashlight off, eyes fully adapted | ~20 |
| Night, flashlight on, inside the beam | 80–90 |
| Night, flashlight on, outside the beam | ~10 (the beam kills your night vision) |

## Rules
- The player can turn the flashlight off (**F** in the test scene).
- Turning it off starts eye adaptation: visibility climbs from ~10 to ~20
  over about **one minute**. Turning it back on resets adaptation quickly.
- Being lit is a trade: the beam shows the street but blinds you to
  everything outside it. Adapted eyes see a little of everything.
- The flashlight cone must not be a hard-edged disc. It should feather at the
  rim and light the mist (visible shaft), reading as a torch not a spotlight.

## How it's built (test scene)
- Eye adaptation = `CameraAttributesPractical.exposure_multiplier` driven by
  `test_hud.gd`: 1× with the torch on, climbing to `adapt_gain` (2× = the
  10→20 step) over `adapt_time` (60 s) with it off, snapping back over
  `dazzle_time` (2 s). Godot's built-in auto exposure was tried and rejected:
  it targets mid-grey and turns the night street into daylight.
- Darkness = `Environment.ambient_light_energy` + a `Moon` DirectionalLight.
- Mist = `volumetric_fog_density`; haze = `fog_density`.
- Cone edge = `SpotLight3D.spot_angle_attenuation` (higher exponent = softer rim).
- All of the above are live sliders in `scripts/test/test_hud.gd` (ESC frees
  the mouse). Record the values you like here once they settle:

| Knob | Value |
|---|---|
| Mist | |
| Haze | |
| Ambient | |
| Moon | |
| Flashlight angle / edge / energy / range | |
| Eye adapt gain / time | |

## Open
- The multiplier is global: it also brightens the torch beam while adapted,
  so switching the torch on when fully adapted should dazzle for a moment.
  That is what `dazzle_time` gives; tune it by feel.
- Minimap: GTA 5 style for now (heading-up, ~30 m radius). Mads to find a
  better reference.
