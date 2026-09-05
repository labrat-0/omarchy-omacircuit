# Omacircuit

A live-track puzzle as an Omarchy shell plugin. The cars never stop. The only
move is turning a tile under them, and the tile a car is standing on is the one
tile that costs you the run.

It opens as an ordinary window, so Hyprland tiles it with everything else.
Nothing is bundled, and every color comes from the active Omarchy theme, so
the board recolors with the desktop.

## Preview

<p align="center">
  <video src="https://github.com/labrat-0/omarchy-omacircuit/raw/master/docs/omacircuit-demo.mp4" controls muted width="900"></video>
</p>

<p align="center">
  <em>
    If the player does not load,
    <a href="docs/omacircuit-demo.mp4">watch the demo (MP4)</a>.
  </em>
</p>

<p align="center">
  <img src="preview.png" alt="Omacircuit on Endurance: three cars, coins, obstacles, and a live route bending toward a hazard" width="900">
</p>

<p align="center">
  <img src="docs/board-lap.png" alt="A fresh Endurance board: the rim circuit is safe forever and reaches no interior tile" width="440">
  &nbsp;
  <img src="docs/how-it-works.png" alt="The in-game help overlay, reached with ?" width="300">
</p>

```bash
omarchy plugin add https://github.com/labrat-0/omarchy-omacircuit --enable
```

That adds a 🏁 button to the bar. Click it, or:

```bash
omarchy-shell shell toggle io.github.labrat-0.omacircuit
```

The plugin is pure QML on modules Omarchy's shell already ships. It does not
reach the network, does not change `~/.config/omarchy/shell.json` itself, and
writes only its own high-score file under `~/.local/state/omacircuit/`.

## How it plays

The track starts as a plain circuit around the rim. It is safe forever and
reaches no interior tile, so the cars will lap it all day and collect nothing.
Coins land only where the cars are *not* already going, and expire on a timer,
so every coin costs a reroute by construction.

Each tile cycles through three states: a crossing, one diagonal deflector, the
other. Every tile carries rail on all four edges, so a click can never leave a
rail end hanging; all it changes is which way traffic bends.

The board wraps rather than ending — drive off one edge and the car reappears
on the opposite one, still mid-lap. There is no wall. What you have to avoid
instead is fixed on the board from the start: a handful of obstacles, placed
once per game on cells the opening loop doesn't already reach. Cruise has
none; the other levels add more of them the bigger the board gets.

The colored trail ahead of each car is where it is actually going, fading with
distance. Where a bent route is about to drive into an obstacle, the trail
turns red and the last safe tile pulses. That preview is the difference
between a puzzle and a guess: the two-flip move is invisible without it.

Three ways to wreck a car:

- Turn the tile a car is standing on. The cursor turns red when it is on one.
- Drive a car into an obstacle.
- Put two cars in the same place.

Any of those costs the run outright on Cruise, which never has a second car
to fall back on. Everywhere else, a wreck with a spare car still on the board
costs only that car — it's gone, the board shakes and flashes exactly like a
real wreck, and the lap keeps going with whatever traffic is left. A row of
dots in the header, one per life the level can field, tracks this at a
glance: filled in that car's own color while it's alive, hollow once it's
gone. The run itself only ends when the last car goes.

A wrecked car isn't gone for the rest of the run, either. Once you've lost
one, the next six coins you collect earn it back — the next hollow dot fills
in with the coin color as that count climbs — up to the level's own cap on
how many cars it ever fields. Score alone stops being what adds a car the
moment you've lost one; a flat run of coins does instead, so recovering a
life is a real goal rather than an automatic side effect of playing on.

## One circuit, no modes

There used to be Versus and Tag, handing the second car to a search-based
opponent. Both are gone: turning the circuit itself into a chore every few
minutes wore thin faster than the puzzle did, and a mode switch is one more
thing to look at instead of at the board. There is exactly one way to play now.

The traffic is the difficulty ramp instead. Every board starts with a single
car; on Circuit and Grand Prix, collecting enough coins earns another, up to
three, so a board that opens nearly empty is dense with near-misses the longer
you keep it alive without ever touching a settings screen. Cruise never adds a
second car, so the collision rule does not exist there at all. Two cars sharing
a tile a little wider than a crash flashes as a near miss rather than nothing,
so the traffic getting busier is something to watch, not just survive.

There is no online multiplayer and none is planned here. Random matchmaking
needs a server with a lobby, presence and state sync that somebody hosts and
pays for, which is a different project from a shell plugin.

## Layouts

Every board used to open identically, so a level had exactly one board and you
had seen all of it after a single run. Each game now picks one of four layouts,
which weld a handful of interior tiles into fixed geometry you have to route
around:

| Layout | What it does |
| --- | --- |
| Open | The bare circuit. The original board. |
| Pillars | An interior lattice of fixed crossings. |
| Spine | A fixed column with one gate left open in it. |
| Chicane | Two locked deflectors set against each other. |

Two rules keep a layout from breaking the game. Locked cells are strictly
interior, so the opening rim circuit is never touched and the start is always
safe. And they default to crossings, which cars pass straight through: welding a
tile removes the ability to *turn* on it without removing the ability to *cross*
it, so nowhere becomes unreachable. All twelve layout-by-level combinations are
checked for both properties.

Welded tiles are warm where the rest of the board is cool, and refuse a turn by
flinching rather than by killing you. The occupied rule is the one that costs a
run; welded geometry is just geometry.

## Levels

Press `1`, `2`, `3`, `4`, or click the chip in the header. Each level moves the
board, the clock and the traffic together, because what makes this hard is how
much of the board is off-limits at once. Best score, and the top five scores,
are kept per level.

| Level | Board | Pace | Coin life | Extra cars | Obstacles | Route shown |
| --- | --- | --- | --- | --- | --- | --- |
| Cruise | 6x5 | 1020ms/tile | 24s | never | 0 | 16 tiles |
| Circuit | 8x6 | 850ms/tile | 16s | at 5 and 12 coins | 1 | 10 tiles |
| Grand Prix | 10x7 | 680ms/tile | 12s | at 3 and 8 coins | 2 | 6 tiles |
| Endurance | 12x8 | 680ms/tile | 12s | at 4 and 9 coins | 3 | 6 tiles |

Cruise never adds a second car and never places an obstacle, so the only way
to lose there is turning the tile a car is standing on — it stays the
zero-pressure level that just teaches the deflector. Its preview also runs far
enough ahead to show both halves of a two-flip move before you commit to
either. Endurance is the same pace as Grand Prix on purpose: the
difficulty there is meant to come from having twice the board to route across,
not from also being faster on top of that — piling both on at once is what made
Circuit and Grand Prix feel unfair rather than hard.

## High scores

Every wreck that beats the fifth-best run on that level (or every wreck at
all, until a level has five) stops for a name: type it normally, up to eight
characters, `Enter` to save it or `Escape` to skip. The board for whichever
level you just played sits on the wrecked screen after that, win or not, so
the number you were chasing stays on screen instead of disappearing the
moment you miss it. Kept per level, five deep, alongside the single best
score in the header.

Gold, silver and bronze medals mark the top three, both on that post-wreck
list and in a live top-three strip above the board during play, so the run
you're chasing is visible while you're still chasing it, not just after.

## Start menu

Opens on launch: the level's top three, and a pick of which of the three
car silhouettes and colors is yours. Whichever you choose stays `cars[0]`
for the run — the one that gets the light-to-dark paint job instead of a
flat tint — and the other two fill in with the remaining colors for
traffic. The pick is remembered between sessions.

Arrows (or click) to choose, `Space` or `Enter` to start. Reopen it anytime
mid-run from the **garage** button under the board — closing it again drops
you back into the same run exactly where you left it, nothing resets.

## Look

Neon on near-black. The board is drawn as a faint circuit lattice and every
live thing on it is three stacked strokes on the same curve: a wide, nearly
transparent halo, the hue itself, then a near-white core. That is the whole
glow trick, and it costs nothing but draw calls.

Surfaces come from the active Omarchy theme, but the playing pieces do not.
Cars, coins and danger are pinned and saturated, because a neon set that drifts
with an arbitrary accent stops being neon, and three cars that have to be told
apart at a glance cannot be three tints of one accent. The idle grid gives up
the cyan so a live route can own it.

Neon is additive, which means it only works on a dark ground: a low-alpha halo
over black adds light, but the same wash over white adds nothing and the whole
three-layer stack collapses into a pale smudge. On a light theme the halos
therefore switch off, the "core" runs toward ink instead of toward white, and
the car's halo becomes a knockout in the board color. The same code draws neon
in the dark and line work on paper.

The grid is a field of dots at the tile corners rather than a lattice of
outlined boxes, and idle track is kept faint on purpose: every tile is a
crossing at rest, so anything stronger turns the board into one flat lattice and
leaves the live route nothing to stand out against.

The frame is sized to the board rather than to the space available, and the
live numbers sit directly under it. Filling the slot left a tall empty rectangle
above and below the play area that read as unfinished layout rather than as
margin, and the header had its whole right half empty until the level picker
moved over to it.

The cars are die-cast racers seen from above: a narrow body with the wheels
stuck out past it and the rear pair visibly fatter than the front, plus a front
and rear wing. Three silhouettes (Formula, Stocker, Speeder) rather than three
tints, because on a board where two cars can be a few pixels apart, hue alone
does not separate them and a colorblind reading collapses two of them outright.
Yours is the one with the paint job: a light-to-dark gloss gradient across the
body instead of the flat tint the traffic cars use, and teal rather than the
purple it started as — a single flat color didn't read as "yours" among the
traffic, and the gradient is what fixes that, not the hue by itself.

Coins carry the **official Omarchy mark**, struck into the face as a darkened
cut of the coin's own metal. It is the real asset off the installed tree
(`$OMARCHY_PATH/icon.png`), colorized at runtime, and its width tracks the same
factor the disc's does so it turns with the coin instead of sitting on top of it.

Each car leaves a **dot matrix wake**: positions snapped to a lattice of eight
points per cell, a dot added only when the car crosses onto a new point, age
carried by brightness alone so the dots stay uniform. The dedupe is also what
makes it cheap, since the array is rebuilt once per lattice crossing rather
than once per frame.

Nothing highlights the tile a car is standing on. A box tracking the car around
the board was the loudest thing on screen and it was saying something the cursor
already says: the cursor turns red when it is on a car, which is the only moment
the occupied rule can cost you anything.

A wreck flashes the board, shakes it, and scatters the car. The game-over scrim
waits for that to finish before it fades in, because drawing it immediately put
it straight over both.

## Keys

| Key | What |
| --- | --- |
| Arrows, or `hjkl` | Move the cursor |
| `Space`, `Enter` | Turn the tile under the cursor |
| Click | Turn that tile, and park the cursor on it |
| `1` `2` `3` `4` | Level |
| `p` | Pause |
| `r` | New board |
| `?` | Help |
| `q`, `Escape` | Close |

On an overlay (paused, wrecked, help) `Space` dismisses it instead of turning a
tile, which is the only reading of the key that is never ambiguous on screen.
Entering a high-score name is the one exception: the keys above are
reassigned while you type (up to eight characters) until you confirm or
cancel — see [High scores](#high-scores).

## Why coins avoid the live route

Spawning them uniformly put 60% of coins on Cruise, 50% on Circuit and 43% on
Grand Prix directly onto the untouched rim loop, where the cars collected them
with no input at all: the game twice scored into double figures while nobody was
playing it, and the level meant to teach the two-flip move was the worst
offender. Coins now spawn only on cells outside every car's forward route, which
drops that to zero on all three levels.

## Why the tiles are deflectors and not track pieces

The obvious model is a loop of straights and curves that you rotate. It does not
work, and it is worth writing down why.

Rotating a straight only ever yields a straight. On a Hamiltonian loop that
fills the grid, every tile is load-bearing, so a single rotation derails the car
about 86% of the time within a few laps, and the repair needs four tiles turned
in a specific 2x2 pattern that rotation cannot produce anyway. A search over
every one- and two-tile edit of that board, and of an all-curves board, found
**zero** edits that leave the rails joined up. Every click was a guaranteed
crash a few seconds later, which is not a control scheme.

Deflectors fix it by making connectivity structural rather than something the
player can break. What is left is a game with exactly one atomic move: no single
flip reaches any interior tile, two flips reach all twenty-four of them, and
half of all careless single flips are fatal within a few laps. That gap is the
whole game.

## Install

```bash
omarchy plugin add https://github.com/labrat-0/omarchy-omacircuit --enable
```

That adds a 🏁 button to the bar and toggles the game from there. To bind a
key instead, or to toggle it from a script:

```bash
omarchy-shell shell toggle io.github.labrat-0.omacircuit
```

No external dependencies — the plugin is pure QML, built entirely on modules
Omarchy's shell already ships (`QtQuick.Shapes`, `QtQuick.Particles`,
`QtQuick.Effects`). Nothing to install beyond the plugin itself.

Before publishing a local checkout, the same check the marketplace and
`omarchy plugin add` run:

```bash
omarchy plugin validate .
```

## Removal

```bash
omarchy plugin remove io.github.labrat-0.omacircuit
```

That disables the plugin and deletes the checkout (or unlinks it, if you
installed it as a symlinked clone for development). It also leaves the bar
without its 🏁 button. High scores are kept at
`~/.local/state/omacircuit/state.json` — remove that file too if you want a
clean slate rather than just reinstalling the plugin:

```bash
rm -rf ~/.local/state/omacircuit
```

## What it writes, and what it does not

- `~/.local/state/omacircuit/state.json` — best score and top-five names per
  level, last level, and the car you picked in the garage. Written when a
  best is beaten, a name is saved, the level changes, or you pick a car.

Nothing else on the system is touched. The plugin makes **no network
requests**, needs no extra packages or credentials, does not rewrite
`~/.config/omarchy/shell.json`, and starts no process beyond a `mkdir -p` of
that state directory. Scores are user-owned data, not configuration.

## Developing it

If the plugin directory in `~/.config/omarchy/plugins/` is a **symlink** to a
checkout elsewhere, the shell's file watcher does not follow it, and edits never
trigger the usual auto-reload. Neither `rescanPlugins` nor a disable/enable
cycle helps, because the compiled component is already resident. Load changes
with:

```bash
omarchy restart shell
```

The shell host injects properties into a plugin's root object the way it injects
`shell`, and `omarchyPath` is one of them. Declaring a property of that name here
(readonly, in particular) makes the host's assignment throw and takes the whole
panel down: no window appears, `summon` still answers `ok`, `listPlugins` still
reports the plugin enabled, and the only trace is one line in the shell log:

```
TypeError: Cannot assign to read-only property "omarchyPath"
```

## Where things live

| Path | What |
| --- | --- |
| `manifest.json` | Plugin manifest: `panel` + `bar-widget`, nothing kept loaded |
| `Panel.qml` | The whole game: model, board, window, keys |
| `BarWidget.qml` | The 🏁 bar button; owns no state, just toggles the panel |
| `preview.png` | Marketplace card/detail source (unoptimized screenshot) |
| `docs/` | Extra README screenshots and the demo clip; not used by the marketplace |
| `LICENSE` | MIT |
| `~/.local/state/omacircuit/state.json` | Best score, top-five names, last level, chosen car |
