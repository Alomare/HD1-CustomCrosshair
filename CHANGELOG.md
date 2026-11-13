# Changelog

New, changed, fixed or removed features, one line each, brief and direct. The section for a release becomes the release notes.

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
