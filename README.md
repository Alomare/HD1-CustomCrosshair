# Custom Crosshair

A crosshair mod for HELLDIVERS (2015), for the [Obsidian](https://github.com/Alomare/ObsidianLauncher) mod manager. It replaces the aim cursor of the game with a crosshair built from shapes, with one look between shots and another while aiming, in missions and on the ship. The menu cursor stays as it is.

Every setting is in the Options tab of Custom Crosshair in Obsidian, in three groups. The Idle and Aiming groups open with a live preview of the crosshair, at actual size and magnified, over a mid grey. There is no in-game settings page, and a change applies at the next launch of the game.

Custom Crosshair is a client mod: it works in any lobby, and only this player sees it. It needs no other mod, and works with Integrated Third Person. The option groups and previews need Obsidian 2.0.0 or later; an older Obsidian lists the same options in one list, without previews.

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
- **Shadow**: a copy behind the crosshair, moved down and to the right, with a color, an opacity and an offset.

Sizes are screen pixels at scale 1. Every line lands on whole pixels, so both sides of the crosshair match: an odd thickness centers the crosshair on the pixel under the mouse, and an even one on the corner of that pixel.

## Idle and aiming

The game shows the aiming cursor while the aim button, fire or a throw is held. Between shots the game shows a dimmer cursor when the crosshair option in the game settings keeps the crosshair visible, and hides the cursor otherwise. In that case the cursor flies back to the Helldiver as it shrinks, and the aiming crosshair here does the same. A state set to Game cursor leaves that state to the game. Switching between idle and aiming, the crosshair fades from one look to the other in 0.08 seconds.

## Integrated Third Person

While the third person view of Integrated Third Person is on, the crosshair goes where shots land, idle or aiming as that mod reports, in place of the crosshair from Integrated Third Person. In the top-down view the crosshair follows the mouse as usual. The game has no cursor in third person, so a state set to Game cursor takes the default look there. With **Third person crosshair** off, Integrated Third Person keeps the crosshair of that mod.

## Controllers

On a controller the game shows no cursor in the top-down view, so Custom Crosshair draws nothing there. In third person the crosshair follows the aim of Integrated Third Person on a controller too.

## Previews

`luajit tools/build_previews.lua` rebuilds `preview/idle.svg` and `preview/aim.svg` from the table of rectangles in `src/shapes.lua`, so the preview and the game round every edge alike.

## Tests

`luajit tests/run.lua` runs the offline tests: the pixels of every shape, outlines and shadows; the previews filled in as Obsidian fills them and compared with what the game draws; the options; and, against stand-ins for the game, the cursor swap, drawing at the mouse and at the third person aim point, the cursor flying back, and frames that make no new tables.

## License

MIT
