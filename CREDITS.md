# Credits

Third-party assets shipped with Zombie Game. Every entry here is a licence
requirement, not a courtesy listing — an itch.io page counts as distribution
even for a free build.

See `10-asset-attribution-rules.md` for the full standing rules. Each asset also
carries `asset_*` custom properties on its root object and children, queryable
from the scene tree at runtime. Do not strip them.

---

## Map data

**Copenhagen greybox** — `assets/city/copenhagen_greybox.glb`
Købmagergade / Østergade (Strøget), Copenhagen. Extracted from OpenStreetMap via
the Blosm addon for Blender, cleaned and exported as glTF.

```
Map data © OpenStreetMap contributors, licensed under ODbL 1.0
https://www.openstreetmap.org/copyright
https://opendatacommons.org/licenses/odbl/1-0/
```

## Characters

**Adventurer** — Quaternius, via Poly Pizza. CC0 (public domain).
https://poly.pizza/m/5EGWBMpuXq — `assets/characters/adventurer.glb`, the 3D
shooter's body (seen by the commander) and the planned NPC survivors. Also
present inside `copenhagen_greybox.glb`.

**Zombie** — bachosoftdesign, via Poly Pizza. **CC-BY 3.0: credit required**
("Zombie by bachosoftdesign, CC-BY 3.0, via Poly Pizza"). Supporter-only
download. https://poly.pizza/m/xqEzosAVYX — `assets/characters/zombie.glb`
(+ its `zombie_ColorPalette.jpg`), every 3D zombie variant.

**Man**, **Business Man**, **Hoodie Character** — Quaternius, via Poly Pizza. CC0
(public domain). https://poly.pizza/m/HMnuH5geEG, https://poly.pizza/m/JFrLIKqvCH,
https://poly.pizza/m/gKLBoRsyKe — `assets/characters/man.glb`, `business_man.glb`,
`hoodie.glb`, the 3D NPC survivors.

## Weapons

**Weapons Pack 002 – In Case of Zombies** — CreativeTrio, via Poly Pizza. CC0
(public domain). https://poly.pizza/bundle/Weapons-Pack-002-%E2%80%93-In-Case-of-Zombies-HgTFEJHrwv
Used: Glock → `assets/weapons/pistol.glb`, Shotgun Double Barrel →
`shotgun.glb`, Sniper → `rifle.glb`, Submachine Gun → `uzi.glb`, Baseball Bat →
`bat.glb`.

## First-person arms + torch

`assets/weapons/fp_arms.glb`, baked from `assets/blender/other/arms.blend` by
`assets/blender/other/build_fp_arms.py`. **Source and licence still to be
confirmed** (the .blend's `PP_` node names suggest Poly Pizza) — fill this in
before any distribution.
