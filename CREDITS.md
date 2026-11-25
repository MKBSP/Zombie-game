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

## Props (stand-ins, Nov 2026)

Rough low-poly stand-ins until the art style is set. Scaled to real metres
through each `.glb.import` root scale. Downloaded from Poly Pizza.

**Kay Lousberg**, via Poly Pizza. CC0 (public domain).
- Car Hatchback: https://poly.pizza/m/BG0KAhmGDt → `assets/props/vehicles/car_hatchback.glb`

**Kenney**, via Poly Pizza. CC0 (public domain).
- Construction Barrier: https://poly.pizza/m/4mrO9ueiQr → `assets/props/street/construction_barrier.glb`

**Quaternius**, via Poly Pizza. CC0 (public domain).
- Car: https://poly.pizza/m/unqqkULtRU → `assets/props/vehicles/car_sedan.glb`
- Car: https://poly.pizza/m/Cz6yDaUcM9 → `assets/props/vehicles/car_sedan_b.glb`
- Police Car: https://poly.pizza/m/BwwnUrWGmV → `assets/props/vehicles/car_police.glb`
- Taxi: https://poly.pizza/m/x43lOScTpN → `assets/props/vehicles/car_taxi.glb`
- SUV: https://poly.pizza/m/xsMtZhBkxL → `assets/props/vehicles/suv.glb`
- Pickup Truck: https://poly.pizza/m/qn4grQgHm8 → `assets/props/vehicles/pickup_truck.glb`
- Truck: https://poly.pizza/m/cXw6oiFtZ8 → `assets/props/vehicles/delivery_truck.glb`
- Dumpster: https://poly.pizza/m/PKsbolkZSr → `assets/props/street/dumpster.glb`
- Container Green: https://poly.pizza/m/h5RUr3vlcS → `assets/props/street/container_green.glb`
- Trashcan: https://poly.pizza/m/XSwahu252t → `assets/props/street/trash_can.glb`
- Trash Bag: https://poly.pizza/m/jYrMKg2Q7C → `assets/props/street/trash_bag.glb`
- Trash Bags: https://poly.pizza/m/eitNk4I4R1 → `assets/props/street/trash_bags.glb`
- Cinder Block: https://poly.pizza/m/lLkVKoJsKm → `assets/props/street/cinder_block.glb`
- Traffic Barrier: https://poly.pizza/m/cM3aJPU9NS → `assets/props/street/traffic_barrier.glb`
- Traffic Barrier: https://poly.pizza/m/nugx3heueH → `assets/props/street/traffic_barrier_b.glb`
- Plastic Barrier: https://poly.pizza/m/QAiXMsbWRc → `assets/props/street/plastic_barrier.glb`
- Traffic Cone: https://poly.pizza/m/VGvQupNGtK → `assets/props/street/traffic_cone.glb`
- Barrel: https://poly.pizza/m/MraIiFnpAY → `assets/props/street/barrel.glb`
- Pallet: https://poly.pizza/m/MwOFAOgOhg → `assets/props/street/pallet.glb`
- Fire Hydrant: https://poly.pizza/m/DKkMQbEklp → `assets/props/street/fire_hydrant.glb`
- Damaged Couch: https://poly.pizza/m/ik7UZdELJE → `assets/props/street/damaged_couch.glb`
- Wheels Stack: https://poly.pizza/m/o1MJrkMUPN → `assets/props/street/wheels_stack.glb`
- Tree: https://poly.pizza/m/QVOop92WmG → `assets/props/nature/tree.glb`
- Tree: https://poly.pizza/m/t9KbsfYdXz → `assets/props/nature/tree_b.glb`
- Dead Tree: https://poly.pizza/m/n8FhMgMldD → `assets/props/nature/dead_tree.glb`
- Dead Tree: https://poly.pizza/m/oM95bD8buf → `assets/props/nature/dead_tree_b.glb`
- Twisted Tree: https://poly.pizza/m/9aWlx82xUf → `assets/props/nature/twisted_tree.glb`
- Bush: https://poly.pizza/m/EoTERLq3z2 → `assets/props/nature/bush.glb`
- Grass: https://poly.pizza/m/vUJjrRsFp4 → `assets/props/nature/grass.glb`
- Grass Wispy: https://poly.pizza/m/Msr9zx66VU → `assets/props/nature/grass_wispy.glb`
- Tall Grass: https://poly.pizza/m/JSIYtscPmP → `assets/props/nature/tall_grass.glb`
- Fern: https://poly.pizza/m/jqcanvH7D6 → `assets/props/nature/fern.glb`
- Plant Big: https://poly.pizza/m/uwJ1rwrZlB → `assets/props/nature/plant_big.glb`

**Bus**, Poly by Google, via Poly Pizza. **CC-BY 3.0: credit required**
("Bus by Poly by Google, CC-BY 3.0, via Poly Pizza"). https://poly.pizza/m/4CPpvEmrMoF → `assets/props/vehicles/bus.glb`

**Shopping cart**, Poly by Google, via Poly Pizza. **CC-BY 3.0: credit required**
("Shopping cart by Poly by Google, CC-BY 3.0, via Poly Pizza"). https://poly.pizza/m/4lhRcMbl1pw → `assets/props/street/shopping_cart.glb`

