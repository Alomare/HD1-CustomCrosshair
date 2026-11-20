# Changelog

New, changed, fixed or removed features, one line each, brief and direct. The section for a release becomes the release notes.

## 1.0.1

- Fixed: In third person with Eyes of Liberty, the crosshair shows while the Helldiver is down or carries something, as both still allow shooting.

## 1.0.0

- New: Dot size options for the idle and aiming crosshairs, set apart from the line thickness.
- Changed: In third person with Eyes of Liberty, the crosshair shows only while the Helldiver can shoot: not while dead, down, carrying, dropping in the Hellpod, putting in a stratagem or looking at the map.
- Changed: The hitmarker sound is quieter across the whole volume range: 0.5 now plays as 0.3 did.
- Changed: New defaults: a circle when idle, a cross with a dot when aiming, a wider aiming gap, and larger, thicker hitmarker lines at a sound volume of 0.5.

## 0.7.1

- Changed: The hitmarker sound is much quieter, and the volume setting changes it more evenly across the range.

## 0.7.0

- New: Hitmarker sound: a short sound plays with every mark the hitmarker shows, with a volume setting.
- Changed: Aiming gap scales with spread now places the arms at the edge of the real spread of the weapon on screen, in third person and in the top-down view.

## 0.6.4

- Changed: a shorter description in Obsidian and the store.

## 0.6.3

- New: an icon in Obsidian.
- Changed: works with Eyes of Liberty, the new name of Unleashed Camera, and still with the older ids.

## 0.6.2

- Changed: works with Unleashed Camera 0.8.0 and later, under the new id, and still with the old one.

## 0.6.1

- Changed: the options name Unleashed Camera, the new name of Integrated Third Person.

## 0.6.0

- New: the crosshair fades out while sprinting in Integrated Third Person 0.6.0 and later.
- New: First person crosshair option, for the first person camera of Integrated Third Person. Off leaves first person with no crosshair.
- New: Laser spin option, on by default. While a laser weapon fires, the crosshair spins up to one turn a second, and winds down over about half a second once firing stops, ending upright.
- Changed: new default look: a dot between shots, and a longer cross with a wider gap while aiming, both with a soft shadow. The hitmarker is smaller and thicker by default, and the kill mark a little bigger.
- Fixed: with Aiming gap scales with spread, the gap stayed open after firing until the next shot, instead of closing as the spread recovers.

## 0.5.0

- New: Idle length and Aiming length set how long each line is, 8 pixels by default. Circles, brackets and the chevron grow with it.
- Changed: new default look. Idle is a faint white circle 3 pixels thick; aiming is a white cross 3 pixels thick with a thin outline and a soft shadow; hit marks are white and kill marks red, with no outline. Settings already saved stay as they are.
- Changed: in third person with Integrated Third Person 0.4.2 or later, the aiming crosshair also shows while fire or a throw is held, as in the top-down view.

## 0.4.0

- New: Aiming gap scales with spread, on by default. The aiming gap opens by up to 12 pixels as the spread of the weapon in hand grows while firing, and closes as the spread settles.
- Changed: number settings go in steps of 0.01, and every one starts at 0. Shadow blur keeps whole pixels.

## 0.3.1

- Fixed: the game cursor no longer shows over the crosshair in the top-down view.

## 0.3.0

- Changed: hit marks are red, as kill marks are, and start at 60% opacity.
- Changed: kill marks are solid and one and a half times the size of hit marks.
- Changed: hitmarker lines are twice as long by default.
- New: Hit opacity, Kill opacity and Kill mark scale options.

## 0.2.0

- New: hitmarker, four diagonal lines around the crosshair that fade out after a hit or a kill. Options for hits, kills, which weapons count, hit and kill color, size, gap, thickness, fade time and outline, with a live preview. Needs Obsidian API.
- New: shadow size, spread and blur.

## 0.1.1

- Changed: the idle and aiming crosshairs fade into each other in 0.08 seconds.

## 0.1.0

- New: replaces the aim cursor of the game with a crosshair built from shapes, with one look between shots and another while aiming, in missions and on the ship.
- New: shapes for each look: cross, cross with dot, dot, circle, circle with dot, circle with cross, T, chevron, brackets, the game cursor or none, with scale, gap, thickness, color, opacity, outline and shadow.
- New: option groups in Obsidian with live previews of the crosshair. The groups and previews need Obsidian 2.0.0.
- New: with Integrated Third Person, the crosshair goes where shots land.
