# Custom Crosshair

A crosshair mod for HELLDIVERS (2015), for the [Obsidian](https://github.com/Alomare/ObsidianLauncher) mod manager. It replaces the aim cursor of the game with a crosshair built from shapes, with one look between shots and another while aiming, in missions and on the ship. The menu cursor stays as it is. A hitmarker flashes around the crosshair when a shot from this player hurts or kills an enemy.

Every setting is in the Options tab of Custom Crosshair in Obsidian, in four groups. The Idle and Aiming groups open with a live preview of the crosshair, at actual size and magnified, over a mid grey, and the Hitmarker group with the mark of a hit and of a kill. There is no in-game settings page, and a change applies at the next launch of the game.

Custom Crosshair is a client mod: it works in any lobby, and only this player sees it. It needs Obsidian API, which Obsidian switches on with it, for the hits of the hitmarker, and works with Integrated Third Person. The option groups and previews need Obsidian 2.0.0 or later; an older Obsidian lists the same options in one list, without previews.

## Settings

**General**

- **Custom crosshair**: on or off.
- **Third person crosshair**: with Integrated Third Person, draws this crosshair where shots go, in place of the one from that mod.

**Idle** and **Aiming** each have the same settings, kept apart:

- **Shape**: cross, cross with dot, dot, circle, circle with dot, circle with cross, T (a cross without the top arm), chevron, brackets, Game cursor (the cursor of the game for that state) or None.
- **Scale**: the whole crosshair, outline and shadow included.
- **Gap**: pixels between the center line and the arms. Circles, brackets and the chevron sit wider with a larger gap.
- **Thickness**: line width in pixels. The dot is twice as wide.
- **Color** and **Opacity**.
- **Outline**: a border around every line, with a color and a thickness.
- **Shadow**: a copy behind the crosshair, moved down and to the right, with a color, an opacity and an offset, and three more settings:
  - **Shadow size**: scales the shadow around the center of the crosshair, from half to twice the size of the lines. At 1 the shadow matches the lines.
  - **Shadow spread**: widens the shadow by up to 6 pixels on every side, past the outline.
  - **Shadow blur**: up to 3 pixels of soft edge, made of rings of fainter copies of the shadow, eight copies to a ring and one ring for each pixel. At 0 the edge stays sharp.

**Hitmarker**

- **Hitmarker**: on or off. Off, nothing listens for hits.
- **Show on hits** and **Show on kills**: which events show a mark. A kill shows over a hit that is still fading.
- **Hits from**: Weapons in hand counts shots from the primary, the sidearm and the support weapon. Everything also counts rockets, grenades, mines, sentries and stratagems of this player. The choice applies to kills too.
- **Hit color** and **Kill color**. The kill color starts as the red of the kill marker in Third Person Camera.
- **Hitmarker size**: length of each of the four diagonal lines, in pixels.
- **Hitmarker gap**: distance from the center of the crosshair to the inner end of each line, along the diagonal.
- **Hitmarker thickness**: width of the lines.
- **Hitmarker time**: how long a mark takes to fade out, from 0.1 to 1.5 seconds. A new hit starts the fade again.
- **Hitmarker outline**: a black border one pixel wide.

Sizes are screen pixels at scale 1. Every line of the crosshair lands on whole pixels, so both sides match: an odd thickness centers the crosshair on the pixel under the mouse, and an even one on the corner of that pixel. The blur copies move by whole pixels too. The default size, spread and blur draw the same shadow as Custom Crosshair 0.1.

## Idle and aiming

The game shows the aiming cursor while the aim button, fire or a throw is held. Between shots the game shows a dimmer cursor when the crosshair option in the game settings keeps the crosshair visible, and hides the cursor otherwise. In that case the cursor flies back to the Helldiver as it shrinks, and the aiming crosshair here does the same. A state set to Game cursor leaves that state to the game. Switching between idle and aiming, the crosshair fades from one look to the other in 0.08 seconds.

## Hitmarker

A hit counts when it costs an enemy health, so a shot that armor stops shows nothing. Hits come from Obsidian API, which hears every hit a player of this machine lands, whichever machine runs the enemy, so the hitmarker works for the host and for everyone else in a lobby. Kills come from the message the game sends to the machine of the killer. Only the main player of this machine counts: hits from teammates, bots and a second controller never show, and neither do hits on teammates.

The mark shows around the crosshair, centered on the crosshair: at the mouse in the top-down view, and at the aim point of Integrated Third Person in third person. With both states set to Game cursor, the mark shows around the game cursor, and in third person around the crosshair of Integrated Third Person. While no crosshair is up, as in menus, on the map or between shots with the game hiding the cursor, no mark shows. In third person the mark needs **Third person crosshair** on.

## Integrated Third Person

While the third person view of Integrated Third Person is on, the crosshair goes where shots land, idle or aiming as that mod reports, in place of the crosshair from Integrated Third Person. In the top-down view the crosshair follows the mouse as usual. The game has no cursor in third person, so a state set to Game cursor takes the default look there. With **Third person crosshair** off, Integrated Third Person keeps the crosshair of that mod.

## Controllers

On a controller the game shows no cursor in the top-down view, so Custom Crosshair draws nothing there. In third person the crosshair follows the aim of Integrated Third Person on a controller too.

## Previews

`luajit tools/build_previews.lua` rebuilds `preview/idle.svg`, `preview/aim.svg` and `preview/hitmarker.svg` from the table of rectangles in `src/shapes.lua` and the lines in `src/hitmarker.lua`, so the preview and the game round every edge alike. Blur copies in the previews are copies of the shadow moved by the same whole pixels as in the game.

## Tests

`luajit tests/run.lua` runs the offline tests: the pixels of every shape, outlines, shadows and blur; the hitmarker lines; the previews filled in as Obsidian fills them, within the limits of the Obsidian previews, and compared with what the game draws; the options; and, against stand-ins for the game and Obsidian API, the cursor swap, drawing at the mouse and at the third person aim point, the cursor flying back, hits and kills of this player and of others, the fade, and frames that make no new tables.

## License

MIT
