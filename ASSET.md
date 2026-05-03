# Asset Task List: Kang Parkir

All tasks are for Roblox Studio-compatible assets (`.rbxm`, `.fbx`, or built in-Studio).
Low-poly target. Mobile performance budget enforced on all models.

---

## Legend

- [ ] = Not started
- [x] = Done
- Priority: **P1** = Blocking (needed for first playtest) | **P2** = Core (needed for full feature) | **P3** = Polish

---

## 1. Environment

### 1.1 Map — Street Layout

- [ ] **P1** Ground plane — asphalt road with faded lane markings (decal texture)
- [ ] **P1** Sidewalk slabs — left and right side, cracked texture variant
- [ ] **P1** Curb/kerb edge pieces — modular, tileable
- [ ] **P1** Parking lot ground zones — painted grid lines per zone (4–8 zone variants)
- [ ] **P2** Wall segments — shophouse facades, tileable, 3 texture variants (cream, lime-washed, peeling)
- [ ] **P2** Rooftop overhangs — flat awning, corrugated metal variant
- [ ] **P3** Puddle decals — for Monsoon Rain event floor visual
- [ ] **P3** Neon signage — "PARKIR", "WARUNG", karaoke sign (emissive texture)

### 1.2 Street Props

- [ ] **P2** Satay cart — low-poly, distinct silhouette, 1 colorway
- [ ] **P2** Martabak / es teh stall — low-poly food cart
- [ ] **P2** Plastic chairs (stack of 3) — background clutter
- [ ] **P2** Hand-painted "PARKIR" wooden board — prop, 2 variants (fresh, worn)
- [ ] **P2** Cardboard box stack — generic clutter, 2 size variants
- [ ] **P2** Gas canister (LPG) — small cylindrical prop
- [ ] **P2** Potted plant (tropical) — low-poly, 2 variants
- [ ] **P2** Utility pole with cables — tall, background element
- [ ] **P3** Hanging banner (cloth strip) — animated waving via `PrismaticConstraint` or bone rig
- [ ] **P3** Trash bag pile — corner clutter

### 1.3 Infrastructure

- [ ] **P1** Traffic spawn node marker (invisible in-game, editor-visible only)
- [ ] **P1** Traffic despawn node marker (same)
- [ ] **P1** Parking lot zone boundary volumes (4–8 zones, `Part` with transparent `BrickColor`)
- [ ] **P1** Hiding volume parts — 4–6 placed at alley/shop positions, semi-transparent
- [ ] **P2** Bank terminal kiosk — low-poly ATM/counter model, distinct color (green or gold)
- [ ] **P2** In-match shop vendor stall — small counter, distinct from Bank terminal
- [ ] **P3** Street lamp — static, emissive at night (if day/night cycle added later)

---

## 2. Vehicles

All vehicles are multi-part assemblies with a defined `PrimaryPart` (chassis base).

### 2.1 Scooter

- [ ] **P1** Base model — 2×4 stud footprint, low-poly, upright
- [ ] **P1** Rigged as `Model` with `PrimaryPart = Chassis`
- [ ] **P2** 3 color variants (red, blue, white)
- [ ] **P3** Idle jiggle animation (subtle handlebar oscillation)

### 2.2 Sport Bike

- [ ] **P1** Base model — 3×5 stud footprint, sportier silhouette than Scooter
- [ ] **P1** Helmet weld point — `Attachment` on seat/rear rack for helmet asset
- [ ] **P1** Helmet prop — separate weld-able `Model`, distinct shape (full-face helmet)
- [ ] **P2** 3 color variants
- [ ] **P3** Helmet can be knocked off and bounce as physics object

### 2.3 Family Car

- [ ] **P1** Base model — 8×12 stud footprint, boxy MPV silhouette
- [ ] **P1** Rigged as `Model` with `PrimaryPart`
- [ ] **P2** 2 color variants
- [ ] **P3** Window decal (family sticker joke)

### 2.4 Aggro SUV

- [ ] **P1** Base model — 9×14 stud footprint, boxy, imposing
- [ ] **P2** Distinct front grill / bull-bar detail (signals it is dangerous)
- [ ] **P2** Angry face decal for driver window (signal vehicle is in "Aggro" path-block state)
- [ ] **P3** 2 color variants

### 2.5 VIP Supercar

- [ ] **P2** Base model — 10×15 stud footprint, sleek, low chassis
- [ ] **P2** Permanent gold sparkle `ParticleEmitter` attached to hood
- [ ] **P2** QTE prompt UI billboard (used during placement QTE, see TASKS.md)
- [ ] **P3** Distinct paint — pearl white or deep red metallic

---

## 3. Characters

### 3.1 Player Character

- [ ] **P1** Base rig — standard R15 Roblox rig (use default, no custom mesh needed at v1.0)
- [ ] **P1** Default vest overlay — opaque `MeshPart` over torso, neutral gray
- [ ] **P2** Vest cosmetic variants:
  - [ ] Neon Construction vest (orange + reflective strips)
  - [ ] Leather Jacket vest
  - [ ] Cyberpunk UI vest (dark + glowing circuit decal)
  - [ ] Gold Foil vest
  - [ ] Street Camo vest
- [ ] **P2** Per-player whistle VFX attachment point — `Attachment` at character mouth
- [ ] **P3** Custom walk animation — hunched, aggressive strut
- [ ] **P3** Custom idle animation — impatient foot-tap

### 3.2 Helmet Thief NPC

- [ ] **P1** Base rig — R15 humanoid, hoodie + beanie outfit mesh
- [ ] **P1** Idle animation — exaggerated "sneaky" side-to-side look
- [ ] **P1** Walk animation — tip-toe shuffle
- [ ] **P2** Rummage animation — crouching, hands moving (plays during 3s Interact state)
- [ ] **P2** Ragdoll state — physics rig enabled (no bespoke animation; engine handles it)
- [ ] **P2** Flee animation — panicked sprint
- [ ] **P3** Facial decal — shifty eyes, exaggerated expression

### 3.3 Satpol PP NPC (Police)

- [ ] **P1** Base rig — R15 humanoid, olive-green uniform mesh
- [ ] **P1** Beret or cap prop on head
- [ ] **P1** Run animation — authoritative sprint
- [ ] **P2** "Caught" animation — points at player, blows whistle
- [ ] **P3** Facial decal — stern expression

---

## 4. VFX & Particles

- [ ] **P1** Whistle VFX — radial ring pulse from player mouth `Attachment`, default white/blue
- [ ] **P1** Gold Whistle VFX variant — same rig, gold/yellow color (VIP Whistle gamepass)
- [ ] **P1** Dash trail — directional speed lines, short duration (~0.3s)
- [ ] **P2** Payout coin burst — "+N" floating text + small coin particles (fires on payout)
- [ ] **P2** Tip-over impact dust cloud — fires when vehicle tips
- [ ] **P2** Domino impact flash — brief white flash on each vehicle in domino chain
- [ ] **P2** Ragdoll hit flash — brief red screen tint (client-local)
- [ ] **P2** Rain particle system — vertical falling drops, medium density, fires globally during Monsoon
- [ ] **P2** Spike Strip deploy VFX — small spark effect on placement
- [ ] **P3** Neon trail cosmetic variants (walk + dash): smoke, sparks, coin shower, neon line
- [ ] **P3** Flash Mob confetti burst — fires at event start, short duration

---

## 5. UI Assets

- [ ] **P1** Shift Tracker frame — HUD panel, minimal, fits top-center
- [ ] **P1** Stamina bar texture — fill gradient (green → yellow → red)
- [ ] **P1** Threat indicator arrow — red arrowhead sprite, 3 opacity levels
- [ ] **P1** Tug-of-War bar — horizontal divided bar, blue/red halves, center pin
- [ ] **P2** Spatial grid overlay texture — semi-transparent white grid tile, seamless
- [ ] **P2** Payout popup text style — bold, outlined, gold color
- [ ] **P2** Penalty popup text style — bold, outlined, red color
- [ ] **P2** Event announcement banner — full-width slide-in panel, distinct per event (3 variants)
- [ ] **P2** In-match shop UI panel — item card layout for 3 consumable slots
- [ ] **P2** Bank terminal UI — simple deposit confirmation dialog
- [ ] **P2** Post-session payout screen — shift summary layout with top earner callout
- [ ] **P3** Skill Tree UI panel — branch/node layout, lock/unlock state icons
- [ ] **P3** Syndicate UI panel — member list, contribution bar, banner display

---

## 6. Audio Assets

All audio sourced from Roblox-approved audio library or custom uploads (cleared for Roblox ToS).

- [ ] **P1** Whistle blow SFX — 8 pitch variants (C4 through C5 semitones)
- [ ] **P1** "Kaching!" coin SFX — sharp, bright, satisfying
- [ ] **P1** Impact/tackle SFX — body hit thud
- [ ] **P1** Crash/tip-over SFX — metallic clatter
- [ ] **P1** Traffic ambient loop — distant engine rumble, medium density
- [ ] **P2** Helmet thief rummage SFX — cloth rustling, zipper, 3D spatial
- [ ] **P2** Vehicle arrival SFX — short engine idle cue
- [ ] **P2** Ragdoll grunt SFX — player hit reaction
- [ ] **P2** Police siren SFX — loop, fires on Raid event start
- [ ] **P2** Rain ambient loop — heavy rain, fires during Monsoon event
- [ ] **P2** Crowd chanting SFX — loop, fires during Flash Mob event
- [ ] **P2** Tug-of-War win sting — short triumphant stab
- [ ] **P3** Custom whistle cosmetic SFX: Train Horn, Airhorn, Duck Quack, Vuvuzela, Referee Whistle
- [ ] **P3** Background warung music loop — low-volume diegetic music from a nearby stall
