import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Shapes
import QtQuick.Effects
import QtQuick.Particles
import qs.Commons

// Omacircuit, a live-track puzzle for omarchy-shell. Summoned through the host:
//   omarchy-shell shell toggle io.github.labrat-0.omacircuit
// The host calls open(payloadJson) / close() and reads `opened`; it injects
// `shell` right after the Loader resolves (see onShellChanged).
//
// The premise: the cars never stop, and the only move is turning a tile under
// them. The board starts as a plain circuit around the rim, which is safe and
// visits none of the interior, so every coin has to be fetched by bending the
// route while the cars are running.
//
// Why the tiles are deflectors and not track pieces. The obvious model is a
// loop of straights and curves that you rotate. It does not work: rotating a
// straight only ever yields a straight, so on a loop that fills the grid there
// is no legal edit at all, and a search over every one- and two-tile edit of
// both that board and an all-curves board found zero that leave the rails
// joined up. Every click was a guaranteed derail a few seconds later, which is
// not a control scheme. So a tile here carries rail on all four edges and
// decides which way traffic bends: a crossing, or one of two diagonal
// deflectors. Connectivity is then structural and a click can never orphan a
// rail end.
//
// What that leaves is a game with exactly one atomic move. No single flip
// reaches any interior tile, and two flips reach all of them: one to turn a car
// off the rim, one on the far side to catch it before it runs out of the world.
// The route preview is what makes that move legible rather than guesswork, and
// it is why the game is playable at all.
//
// The model is one flat array indexed by cell (`col + row * cols`): `turns`
// counts how many times a tile has been clicked, and the piece is `turns % 3`.
// It is unbounded rather than modulo 3 so the pop animation has something
// monotonic to fire on. Every mutation copies the array and assigns the copy
// back, because a QML `var` property only notifies on assignment.
//
// Cars are mutated in place each frame for cheapness; `frame` is bumped once
// per tick and every car binding reads it, which is what makes them repaint.
// The route is not on that clock: it only changes when a car crosses into a new
// tile or a tile is turned, so it is recomputed at those two moments instead.
Item {
  id: root

  property bool opened: false

  readonly property string selfId: "io.github.labrat-0.omacircuit"

  // Injected by the shell host after the Loader resolves. Used to keep the
  // host's open-flag honest on close(), and to self-restore if the host's
  // panel Instantiator rebuild destroys a visibly-open instance.
  property var shell: null
  onShellChanged: {
    if (!root.opened && root.shell && root.shell.openPanelIds
        && root.shell.openPanelIds[root.selfId] === true)
      root.open("{}")
  }

  // ------------------------------------------------------------------ theme
  //
  // The surfaces share the [menu] tokens so a theme that styles the menu
  // styles this panel too, and the board furniture is all derived from the
  // palette. The playing pieces are not: cars, coins and danger are pinned to
  // an ANSI-ish set with a light and a dark variant, the same trade the shell's
  // own terminal-styled plugins make, because three cars that have to be told
  // apart at a glance cannot be three tints of one accent.
  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property color accent: Color.accent
  property color urgent: Color.urgent
  readonly property int cornerRadius: Style.cornerRadius
  property string fontFamily: Style.font.menuFamily
  property int contentMargin: Style.spacing.panelPadding

  // A color written as a string has no r/g/b members, so the arithmetic in
  // mix() and fade() silently produced NaN and painted opaque black. Every
  // neon core in this file goes through core() -> mix(c, "#ffffff", ...), so
  // the brightest layer of the glow was black on all of them: the cars carried
  // a black slug where their core should be. Qt.lighter at factor 1.0 is the
  // cheapest string-to-color conversion available here.
  function toColor(c) { return typeof c === "string" ? Qt.lighter(c, 1.0) : c }

  function lum(c) { return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b }
  function mix(a, b, t) {
    var A = root.toColor(a)
    var B = root.toColor(b)
    return Qt.rgba(A.r + (B.r - A.r) * t,
                   A.g + (B.g - A.g) * t,
                   A.b + (B.b - A.b) * t, 1)
  }
  function fade(c, a) {
    var C = root.toColor(c)
    return Qt.rgba(C.r, C.g, C.b, a)
  }
  readonly property bool darkSurface: root.lum(root.background) < 0.5

  // The board is deliberately darker than the panel: neon only reads as neon
  // against something close to black, and the glow layers below supply all the
  // brightness the board needs.
  // On a dark theme the board sinks below the panel so the neon has somewhere
  // to burn; on a light one it lifts slightly instead, because there is no
  // "darker than the paper" that still reads as a play area.
  readonly property color boardBg: root.darkSurface
    ? root.mix(root.background, "#000000", 0.45)
    : root.mix(root.background, root.foreground, 0.05)
  readonly property color tileBed: "transparent"
  // The tile-boundary hairlines are background structure, the same as the
  // corner dots, not track — so they take the dot hue too. Before this they
  // matched the rail blue, which meant the whole board (rails, boundary, and
  // background) read as one material with the traffic on top of it, and it
  // took actually separating the corner dots (dotNeon, below) to notice.
  readonly property color gridLine: root.fade(root.dotNeon, 0.16)
  // Ballast is part of the rail, not the chrome, so it takes the resting
  // rail's own hue (railIdle, below) rather than the structural blue
  // everything else on the board uses. Kept very faint now that the rail
  // itself is dots: this is just a hint of a bed under them, not a second
  // line competing with the dots for the same job.
  readonly property color conduit: root.fade(root.railIdle, 0.05)
  // Welded track reads as metal rather than circuit: warm where everything else
  // on the board is cool, so a locked tile is obvious without needing a label.
  readonly property color weldColor: root.darkSurface
    ? root.mix(root.background, "#c9a227", 0.42)
    : root.mix(root.background, "#7a5c00", 0.55)
  readonly property color weldBed: root.fade(root.weldColor, root.darkSurface ? 0.07 : 0.12)
  readonly property color dim: root.mix(root.background, root.foreground, 0.42)

  // Pinned, saturated, and the same in both themes apart from a darkening pass:
  // a neon set that drifts with an arbitrary accent stops being neon.
  // gridNeon is chrome now, not track: the frame, dividers and inactive
  // chip borders. The rail itself moved to its own hues (railIdle/railNeon,
  // below) so recoloring one does not recolor the other.
  readonly property color gridNeon:   root.darkSurface ? "#3f6ea8" : "#1e4c63"
  // An icy electric blue for the rail at rest — track lighting, not slate.
  // Kept out of both the background jade (dotNeon, below) and the frame's
  // navy (gridNeon, above) by leaning much lighter and more saturated than
  // either: this is meant to be the brightest cool color on the board,
  // since it is now drawn as dots rather than a dim stroke and needs to
  // read as "lit" rather than as "the same calm chrome as everything else."
  readonly property color railIdle:   root.darkSurface ? "#7dd3fc" : "#0369a1"
  // The turn flash and the outbound shockwave both use this instead: green,
  // because it is the one color on the board that means "go" and nothing
  // else here claims it. Turning a tile is the one action in the whole game,
  // so the moment it happens gets a color that says exactly that, and
  // showing it on the rail itself is what answers "which way did it just
  // point" without needing a second indicator. Kept out of the resting rail
  // on purpose — green at any alpha strong enough to see reads as loud, and
  // loud is what a turn should announce, not the idle board.
  readonly property color railNeon:   root.darkSurface ? "#22c55e" : "#15803d"
  // The corner dots and hairlines are substrate, not track and not a playing
  // piece. Neutral gray was the safe fix for the grid reading as "the same
  // color as the car," but labrat wanted the dot matrix back to being an
  // actual color rather than gray — and now that the car that collided with
  // it (cyan) has moved to violet, the original jade is safe again: nothing
  // else on the board is teal-green, cyan-family included.
  readonly property color dotNeon:    root.darkSurface ? "#2fae87" : "#1f6b52"
  // Cyan was the collision with the background dots, and violet after it
  // was also rejected on its own merits — two hues burned on the lead car
  // already, so this one is teal, the one wedge of the wheel nothing else on
  // the board sits near: greener than the icy rail-blue, bluer than the
  // jade background, and nowhere close to the other two cars or any UI
  // accent. The lead car also gets a gradient finish instead of a flat fill
  // (see Racer, below) — "why single colored cars" was a fair question,
  // and the answer for the one you're actually flying is that it shouldn't
  // be, even though the two traffic cars still are.
  readonly property var carHues: root.darkSurface
    ? ["#2dd4bf", "#f472b6", "#a3e635"]
    : ["#0f766e", "#be185d", "#4d7c0f"]
  readonly property color coinColor:   root.darkSurface ? "#fbbf24" : "#b45309"
  readonly property color dangerColor: root.darkSurface ? "#ff2d6f" : "#be123c"
  readonly property color cursorColor: root.darkSurface ? "#fb923c" : "#c2410c"
  readonly property var levelHues: root.darkSurface
    ? ["#a3e635", "#22d3ee", "#ff2d6f", "#e879f9"]
    : ["#4d7c0f", "#0e7490", "#be123c", "#a21caf"]

  // A neon core is the hue pushed most of the way to white. Drawn on top of a
  // wider, dimmer stroke of the hue itself, that is the whole trick.
  // Neon is additive: a low-alpha halo over black adds light, but the same wash
  // over white adds nothing, so the whole three-layer stack collapses to a pale
  // smudge on a light theme. The fix is not thinner alphas, it is a different
  // idiom. On light the halos switch off and the "core" runs toward ink rather
  // than toward white, so the same code draws neon in the dark and drawn line
  // work on paper.
  readonly property real glow: root.darkSurface ? 1.0 : 0.0
  // How solid the body of a stroke sits. Paper needs near-opaque ink where a
  // dark board can let the halo do the carrying.
  readonly property real ink: root.darkSurface ? 1.0 : 1.0

  function core(c) {
    return root.darkSurface ? root.mix(c, "#ffffff", 0.62)
                            : root.mix(c, "#000000", 0.42)
  }

  // ------------------------------------------------------------------ racers
  //
  // Three cars have to be told apart on a board where two of them may be a
  // few pixels apart, and hue alone does not survive that: on the light
  // palette the three are all mid-tone, and a colorblind reading collapses
  // two of them outright. So the cars differ by silhouette first and color
  // second. Each is a closed outline in cell units, nose pointing along +x,
  // measured from the middle of the tile; the delegate supplies the heading.
  // Hot Wheels rather than aircraft: a die-cast racer read from above is a
  // narrow body with the wheels stuck out past it, and the rear pair visibly
  // fatter than the front. The exaggeration is the point, so the rear tires and
  // the wing are drawn bigger than any real car would carry them.
  //
  // Each body is a closed outline in cell units, nose pointing along +x,
  // measured from the middle of the tile; the delegate supplies the heading.
  // Wheels and wings are [center x, center y, width, height] in the same units
  // and are laid under the body.
  readonly property var carBodies: [
    // Formula — long nose, shouldered cockpit, waisted tail.
    [[0.36, 0.000], [0.32, 0.022], [0.22, 0.030], [0.15, 0.048], [0.08, 0.086],
     [-0.02, 0.096], [-0.10, 0.078], [-0.16, 0.062], [-0.23, 0.058], [-0.27, 0.030],
     [-0.27, -0.030], [-0.23, -0.058], [-0.16, -0.062], [-0.10, -0.078], [-0.02, -0.096],
     [0.08, -0.086], [0.15, -0.048], [0.22, -0.030], [0.32, -0.022]],
    // Stocker — squared shoulders, a nose that is all grille, a cut tail.
    [[0.30, 0.038], [0.31, 0.070], [0.24, 0.104], [0.12, 0.124], [-0.04, 0.128],
     [-0.16, 0.118], [-0.24, 0.094], [-0.28, 0.052],
     [-0.28, -0.052], [-0.24, -0.094], [-0.16, -0.118], [-0.04, -0.128], [0.12, -0.124],
     [0.24, -0.104], [0.31, -0.070], [0.30, -0.038]],
    // Speeder — one unbroken wedge from the tip to the rear deck.
    [[0.38, 0.000], [0.30, 0.036], [0.18, 0.070], [0.04, 0.098], [-0.08, 0.112],
     [-0.19, 0.108], [-0.25, 0.086], [-0.29, 0.044],
     [-0.29, -0.044], [-0.25, -0.086], [-0.19, -0.108], [-0.08, -0.112], [0.04, -0.098],
     [0.18, -0.070], [0.30, -0.036]]
  ]
  readonly property var carWheels: [
    [[0.17,  0.122, 0.115, 0.056], [0.17, -0.122, 0.115, 0.056],
     [-0.17, 0.150, 0.150, 0.078], [-0.17, -0.150, 0.150, 0.078]],
    [[0.16,  0.132, 0.110, 0.054], [0.16, -0.132, 0.110, 0.054],
     [-0.16, 0.148, 0.140, 0.070], [-0.16, -0.148, 0.140, 0.070]],
    [[0.15,  0.112, 0.100, 0.050], [0.15, -0.112, 0.100, 0.050],
     [-0.17, 0.130, 0.128, 0.064], [-0.17, -0.130, 0.128, 0.064]]
  ]
  readonly property var carWings: [
    // front wing, rear wing
    [[0.29, 0.0, 0.042, 0.230], [-0.26, 0.0, 0.055, 0.300]],
    [[0.26, 0.0, 0.036, 0.190], [-0.26, 0.0, 0.050, 0.265]],
    [[0.30, 0.0, 0.034, 0.170], [-0.25, 0.0, 0.046, 0.215]]
  ]
  readonly property var carNames: ["Formula", "Stocker", "Speeder"]

  readonly property color hoverFill: root.fade(root.cursorColor, 0.10)
  readonly property color lockedLine: root.fade(root.dangerColor, 0.70)
  // Kept faint on purpose. The route preview marks the exact tile where a bent
  // route leaves the board, which is the information that matters; the rim only
  // needs to hint at the edge, not compete with it.
  readonly property color rimLine: root.fade(root.gridNeon, 0.30)

  // ----------------------------------------------------------------- levels
  //
  // The levels are not one ramp with the numbers scaled: each moves the board
  // size, the clock and the traffic together, because the thing that makes this
  // hard is how much of the board is off-limits at once. Cruise never adds a
  // second car, so the collision rule simply does not exist there, and its
  // route preview runs far enough ahead to show both halves of a two-flip move
  // before you commit to either.
  // `tile` is ~20% slower across every level than the original pass — "the
  // speed is too fast" landed after the 3-car relief below was already in,
  // so this is the base pace itself, not just what happens once traffic
  // stacks up.
  readonly property var levels: [
    { key: "cruise",  name: "Cruise",
      cols: 6, rows: 5, tile: 1020, coin: 24000, coinsWanted: 2, second: 999, third: 999, look: 16, obstacles: 0 },
    { key: "circuit", name: "Circuit",
      cols: 8, rows: 6, tile: 850, coin: 16000, coinsWanted: 2, second: 5,   third: 12,  look: 10, obstacles: 1 },
    { key: "grandprix", name: "Grand Prix",
      cols: 10, rows: 7, tile: 680, coin: 12000, coinsWanted: 3, second: 3,  third: 8,   look: 6,  obstacles: 2 },
    // The bigger map asked for outright. Traffic pressure stays level with
    // Grand Prix (same tile pace, thresholds nudged back slightly) rather
    // than escalating further — the extra difficulty here is meant to come
    // from having more board to route across, not from being faster on top
    // of that. Piling speed onto size is exactly the compounding labrat
    // flagged as what makes Circuit hard to control in the first place.
    { key: "endurance", name: "Endurance",
      cols: 12, rows: 8, tile: 680, coin: 12000, coinsWanted: 4, second: 4,  third: 9,   look: 6,  obstacles: 3 }
  ]

  property int level: 1
  readonly property var spec: root.levels[Math.max(0, Math.min(root.levels.length - 1, root.level))]
  readonly property color levelColor: root.levelHues[Math.max(0, Math.min(root.levelHues.length - 1, root.level))]

  function setLevel(i) {
    // Don't abandon a high-score name mid-entry. The chips stay visible on
    // the wrecked card, and a click used to call newGame() which wiped the
    // qualifying run without saving it.
    if (root.highScoreEntry) return
    var n = Math.max(0, Math.min(root.levels.length - 1, i))
    if (n === root.level) return
    root.level = n
    root.newGame()
    root.writeState()
  }

  // ------------------------------------------------------------------- grid

  readonly property int cols: root.spec.cols
  readonly property int rows: root.spec.rows
  readonly property int cellCount: root.cols * root.rows

  readonly property int eN: 1
  readonly property int eE: 2
  readonly property int eS: 4
  readonly property int eW: 8

  function opp(e) { return e <= 2 ? e * 4 : e / 4 }

  function isRim(cell) {
    var x = cell % root.cols, y = Math.floor(cell / root.cols)
    return x === 0 || y === 0 || x === root.cols - 1 || y === root.rows - 1
  }

  // Edge midpoints in unit tile coordinates. A car's path across a tile is a
  // quadratic Bezier from its entry midpoint to its exit midpoint with the
  // control point at the tile center, which draws a clean quarter arc through
  // a deflector and degenerates to a straight line through a crossing.
  function edgeMid(e) {
    if (e === root.eN) return { x: 0.5, y: 0.0 }
    if (e === root.eE) return { x: 1.0, y: 0.5 }
    if (e === root.eS) return { x: 0.5, y: 1.0 }
    return { x: 0.0, y: 0.5 }
  }

  // A point on the same quadratic Bezier `edgeMid` describes, at 0<=t<=1.
  // The route preview samples this rather than stroking the curve, so the
  // circuit reads as the same dot-matrix particle language as the spark wake
  // instead of as a second, competing solid line drawn over the rails.
  function quadPoint(p0, c, p2, t) {
    var u = 1 - t
    return {
      x: u * u * p0.x + 2 * u * t * c.x + t * t * p2.x,
      y: u * u * p0.y + 2 * u * t * c.y + t * t * p2.y
    }
  }

  // The board wraps rather than ending. A car that drives off one edge
  // reappears on the opposite one, same row or column, still mid-lap — there
  // is no more "off the board" to crash into. `isObstacle()`, below, is what
  // replaces it as the thing routing has to actually avoid.
  function neighbor(cell, edge) {
    var x = cell % root.cols
    var y = Math.floor(cell / root.cols)
    if (edge === root.eN) y -= 1
    else if (edge === root.eS) y += 1
    else if (edge === root.eE) x += 1
    else x -= 1
    x = (x + root.cols) % root.cols
    y = (y + root.rows) % root.rows
    return x + y * root.cols
  }

  // ------------------------------------------------------------------ board
  //
  // piece 0 is a crossing, 1 is the "\" deflector, 2 is the "/" deflector.
  // Each carries rail on all four edges, so the only thing a click changes is
  // where traffic goes, never whether the rails meet.

  property var turns: []

  function pieceOf(i) {
    if (i < 0 || i >= root.turns.length) return 0
    return root.turns[i] % 3
  }

  function exitFor(piece, from) {
    if (piece === 0) return root.opp(from)
    if (piece === 1)   // "\"  N<->E, S<->W
      return from === root.eN ? root.eE
           : from === root.eE ? root.eN
           : from === root.eS ? root.eW : root.eS
    // "/"  N<->W, S<->E
    return from === root.eN ? root.eW
         : from === root.eW ? root.eN
         : from === root.eS ? root.eE : root.eS
  }

  // The pairs of rails a piece draws, as [entry, exit] edges.
  function pathsFor(piece) {
    if (piece === 0) return [[root.eN, root.eS], [root.eW, root.eE]]
    if (piece === 1) return [[root.eN, root.eE], [root.eS, root.eW]]
    return [[root.eN, root.eW], [root.eS, root.eE]]
  }

  // A bare circuit around the rim: crossings everywhere, deflectors in the
  // four corners to turn the traffic. It is safe forever and touches no
  // interior tile, which is what forces the player to bend it.
  // ---------------------------------------------------------------- layouts
  //
  // Every board used to open identically: a bare rim circuit with all forty-odd
  // interior tiles interchangeable, so a level had exactly one board and you
  // had seen all of it after one run. A layout locks a handful of interior
  // tiles, which cannot be turned and so become fixed geometry to route around.
  //
  // Two rules keep a layout from being able to break the game. Locked cells are
  // strictly interior, so the opening rim circuit is never touched and the
  // start is always safe. And they default to crossings, which cars pass
  // straight through: a locked crossing removes the ability to *turn* on that
  // tile without removing the ability to *cross* it, so nowhere on the board
  // becomes unreachable.
  property var locked: []

  readonly property var layoutNames: ["Open", "Pillars", "Spine", "Chicane"]
  property int layout: 0
  readonly property string layoutName: root.layoutNames[root.layout % root.layoutNames.length]

  // Returns [{cell, piece}] for the chosen layout. `piece` 0 is a crossing.
  function layoutTiles(which) {
    var out = []
    var C = root.cols, R = root.rows
    var x, y
    var cx = Math.floor(C / 2), cy = Math.floor(R / 2)

    if (which === 1) {
      // Pillars: an interior lattice of fixed crossings. Traffic still flows
      // through them; you simply cannot steer on them.
      for (y = 2; y <= R - 2; y += 2)
        for (x = 2; x <= C - 2; x += 2)
          out.push({ cell: x + y * C, piece: 0 })
    } else if (which === 2) {
      // Spine: a fixed column with one gate left open in it, so crossing the
      // board is free but turning across the spine costs you the gate.
      for (y = 1; y <= R - 2; y++) {
        if (y === cy) continue
        out.push({ cell: cx + y * C, piece: 0 })
      }
    } else if (which === 3) {
      // Chicane: two locked deflectors set against each other. A car sent
      // between them comes out somewhere it did not go in.
      if (C >= 5 && R >= 4) {
        out.push({ cell: (cx - 1) + cy * C, piece: 1 })
        out.push({ cell: (cx + 1) + cy * C, piece: 2 })
        out.push({ cell: cx + (cy - 1) * C, piece: 0 })
      }
    }
    return out
  }

  function buildTrack() {
    var t = new Array(root.cellCount)
    for (var i = 0; i < t.length; i++) t[i] = 0
    t[0] = 2                                  // top-left     S -> E
    t[root.cols - 1] = 1                      // top-right    W -> S
    t[root.cellCount - 1] = 2                 // bottom-right N -> W
    t[root.cellCount - root.cols] = 1         // bottom-left  E -> N

    var lk = new Array(root.cellCount)
    for (var k = 0; k < lk.length; k++) lk[k] = false
    var tiles = root.layoutTiles(root.layout)
    for (var n = 0; n < tiles.length; n++) {
      var c = tiles[n].cell
      // Belt and braces: a layout must never touch the rim, because the
      // opening circuit runs on it.
      if (c < 0 || c >= root.cellCount || root.isRim(c)) continue
      t[c] = tiles[n].piece
      lk[c] = true
    }
    root.turns = t
    root.locked = lk
  }

  function isLocked(i) {
    return i >= 0 && i < root.locked.length && root.locked[i] === true
  }

  // ------------------------------------------------------------------- game

  property string phase: "running"    // running | paused | crashed
  property string crashReason: ""
  property int crashCell: -1
  // A spare car turns a wreck into a lost car instead of a lost run. Once
  // that has happened this game, the normal score-ramp stops being what
  // tops traffic back up (see `collect()`): the ramp's thresholds are
  // absolute scores already climbing regardless, so left alone it would
  // hand the car straight back the moment the next coin landed. Instead a
  // flat run of coins buys the next one back, same as an arcade extra life.
  property bool carLost: false
  property int coinsForLife: 6
  property int coinsSinceCrash: 0
  // The ramp already caps out here for every level but Cruise (whose
  // thresholds are the 999 "never" sentinel) — probing at 900 rather than
  // hardcoding 3 keeps this honest if a level's thresholds ever change.
  readonly property int maxCars: root.carCountFor(900)
  // Bumped on every crash, fatal or not, so the shake/flash/debris can react
  // to a wreck even when it costs only a car and phase never leaves "running".
  property int crashPulse: 0
  property int score: 0
  property var bests: ({})
  property bool helpOpen: false
  // The start menu: up at cold boot, and reopenable via the "garage" button
  // in the live readout. Which silhouette/hue is "yours" (root.cars[0],
  // always the original car — see variantFor()) rather than tied to array
  // position the way traffic cars are.
  //
  // Defaults false and flips true in Component.onCompleted below rather
  // than defaulting true here: the overlay's fade-in only runs off
  // onVisibleChanged, a change signal that never fires for a property's
  // initial constructed value, only for a real transition. Starting this
  // true made the overlay's `visible` true from construction with nothing
  // ever toggling it, so the scrim sat at its declared opacity: 0 forever —
  // technically "shown," but invisible.
  property bool menuOpen: false
  property int chosenCar: 0

  // Each car carries its own `variant` (silhouette + hue) and `player` flag.
  // Index 0 is *not* identity: splicing a wrecked player used to promote the
  // next traffic car into cars[0], which then inherited the player's paint
  // job and silhouette via the old index-based lookup.
  function variantFor(i) {
    var car = root.cars[i]
    if (car && typeof car.variant === "number")
      return Math.max(0, Math.min(2, car.variant | 0))
    if (i === 0) return root.chosenCar
    var others = [0, 1, 2].filter(function(v) { return v !== root.chosenCar })
    return others[(i - 1) % others.length]
  }

  function carColor(i) {
    return root.carHues[root.variantFor(i) % root.carHues.length]
  }

  function hasPlayer() {
    for (var i = 0; i < root.cars.length; i++)
      if (root.cars[i] && root.cars[i].player) return true
    return false
  }

  function nextTrafficVariant() {
    var used = {}
    used[root.chosenCar] = true
    for (var i = 0; i < root.cars.length; i++) {
      if (root.cars[i] && typeof root.cars[i].variant === "number")
        used[root.cars[i].variant] = true
    }
    for (var v = 0; v < 3; v++) if (!used[v]) return v
    return (root.chosenCar + 1) % 3
  }

  function setChosenCar(i) {
    i = Math.max(0, Math.min(2, i | 0))
    if (i === root.chosenCar) return
    root.chosenCar = i
    var traffic = [0, 1, 2].filter(function(v) { return v !== i })
    var t = 0
    var next = []
    for (var k = 0; k < root.cars.length; k++) {
      var c = Object.assign({}, root.cars[k])
      if (c.player) c.variant = i
      else { c.variant = traffic[t % traffic.length]; t++ }
      next.push(c)
    }
    root.cars = next
    root.writeState()
  }

  // Top five per level, `{name, score}` sorted high to low. `bests` above is
  // just "your single best," kept for the header readout; this is the full
  // arcade-style board, keyed the same way.
  property var highScores: ({})
  // Non-null only on the wreck that just qualified: `{text: "..."}`, free
  // text up to 8 characters (handleKey() enforces the length as you type).
  // Cleared by commitHighScore(); newGame() also clears it defensively since
  // the level chips are clickable regardless of phase and a click there
  // would otherwise abandon an entry mid-flight without resetting anything.
  property var highScoreEntry: null

  function qualifiesForHighScore(s, key) {
    if (s <= 0) return false
    var list = root.highScores[key] || []
    if (list.length < 5) return true
    return s > list[list.length - 1].score
  }

  function commitHighScore() {
    var e = root.highScoreEntry
    if (!e) return
    var list = (root.highScores[root.spec.key] || []).slice()
    var name = root.sanitizeName(e.text).trim()
    if (name === "") { root.highScoreEntry = null; return }
    list.push({ name: name, score: root.score })
    list.sort(function(a, b) { return b.score - a.score })
    list = list.slice(0, 5)
    var next = {}
    for (var k in root.highScores) next[k] = root.highScores[k]
    next[root.spec.key] = list
    root.highScores = next
    root.highScoreEntry = null
    root.writeState()
  }

  property var cars: []
  property var coins: []
  // Fixed hazards, placed once per board and never moving or expiring —
  // terrain, not a timer. A plain array of cell indices is enough: unlike
  // coins there is no per-obstacle state to carry, so there is nothing an
  // object would buy over a number.
  property var obstacles: []
  property var route: []
  property int frame: 0

  // One shared phase for the board's "wave" look (the background dot field,
  // the idle track's own dots): a sine sampled at each dot's position with a
  // phase offset, so brightness varies across the board like a wave frozen
  // mid-crossing rather than every dot being the same flat brightness.
  //
  // This used to animate continuously — a Timer stepping it and every dot's
  // `Math.sin()` binding re-evaluating on every step. Measured cost of that
  // was severe: the idle track alone (~1000 items, later a Canvas-per-tile
  // redraw driven by this phase) accounted for roughly half of the whole
  // plugin's CPU even after cutting the item count down and throttling the
  // step rate repeatedly — going from 60fps to 12fps to 4fps each barely
  // moved the needle, which says the animation itself was the cost, not its
  // frequency. A live-desktop panel that pegs a CPU core to animate
  // background dust is not a trade worth making, so the phase is now a
  // fixed constant: the wave shape stays, the animation driving it doesn't.
  // If this needs to move again, it should be a narrow, rare trigger (e.g.
  // only on a turn) rather than a perpetual clock.
  readonly property real wavePhase: 0.7

  // The turn flash, as one shared value rather than one per tile. Only one
  // tile can be mid-flash at a time in practice, so a single `flashCell` +
  // `flashAmount` pair driven by one animation is exactly as expressive as
  // 70 independent per-tile properties and their own animations were, for a
  // tiny fraction of the object count — the same lesson as the track dots.
  property int flashCell: -1
  property real flashAmount: 0
  function triggerFlash(cell) {
    root.flashCell = cell
    flashDecay.restart()
  }
  SequentialAnimation {
    id: flashDecay
    NumberAnimation { target: root; property: "flashAmount"; to: 1; duration: 40 }
    NumberAnimation { target: root; property: "flashAmount"; to: 0; duration: 420; easing.type: Easing.OutQuad }
  }

  // Where each car has just been, as a dot matrix rather than a drawn line.
  // Positions are snapped to a lattice of `dotStep` points per cell and a dot
  // is only added when the car crosses onto a new lattice point, so the wake is
  // a stream of evenly spaced points that traces the real curve through a
  // deflector. The dedupe is also what keeps this cheap: the array is
  // reassigned once per lattice crossing rather than once per frame.
  // The array's own length is the lifetime, oldest at the front.
  property var sparks: []
  // Denser lattice (finer-grained dots) with the trail cap raised to match,
  // so the wake covers the same real distance behind the car at the higher
  // density rather than just getting shorter.
  readonly property int sparksPerCar: 70
  readonly property int dotStep: 12
  property var lastDot: ({})

  // Collection bursts, culled by age in tick(). Each delegate runs its own
  // animation on creation rather than binding to `frame`, so the effect costs
  // nothing while none are alive.
  property var pops: []
  readonly property int popLife: 620

  // Two cars sharing a tile a third of it apart is a crash; a little further
  // than that and it is a near miss, which is worth celebrating rather than
  // only ever punishing the closer failure mode. `missCooldown` is keyed by
  // the unordered car pair so two cars queued behind each other on the same
  // stretch do not flash on every frame they stay this close.
  property var misses: []
  readonly property int missLife: 460
  property var missCooldown: ({})

  // Where the wreck happened, in cells from the board origin, plus a seed so
  // the debris does not scatter the same way twice.
  property var crashPoint: ({ x: 0, y: 0 })
  property real crashSeed: 0

  readonly property int best: root.bests[root.spec.key] !== undefined ? root.bests[root.spec.key] : 0
  readonly property int coinLife: root.spec.coin
  readonly property int coinsWanted: root.spec.coinsWanted

  // Every coin shaves a little off the lap time, but never past the point where
  // a deflector still reads as a turn rather than a blur. The floor moved
  // from 62% of the base pace to 75% — "too fast" was general, not just late
  // in a run, so the top end of the ramp needed raising too, not only the
  // base `tile` values above. Speed and traffic both climbing with score at
  // once is *also* what made three-plus cars feel unmanageable rather than
  // hard — the two were compounding right when there was the most to track.
  // A third car earns 15% back off the clock on top of that, easing exactly
  // the moment that stacking happens without touching the one- and two-car
  // pace at all.
  readonly property real tileTime: {
    var t = Math.max(root.spec.tile * 0.75, root.spec.tile - root.score * 8)
    return root.cars.length >= 3 ? t * 1.15 : t
  }

  // Traffic is the whole difficulty ramp now that there is no opponent to
  // supply pressure: every few coins the board earns another car, up to
  // three, so a board that started nearly empty is dense with near-misses
  // an hour later without the player ever touching a settings screen.
  function carCountFor(s) {
    return 1 + (s >= root.spec.second ? 1 : 0) + (s >= root.spec.third ? 1 : 0)
  }

  // The keyboard cursor. Arrows move it, space turns the tile under it, which
  // means the keyboard can reach the one move the mouse can make.
  property int cursor: 0

  function moveCursor(dx, dy) {
    var x = root.cursor % root.cols
    var y = Math.floor(root.cursor / root.cols)
    x = Math.max(0, Math.min(root.cols - 1, x + dx))
    y = Math.max(0, Math.min(root.rows - 1, y + dy))
    root.cursor = x + y * root.cols
  }

  function newGame() {
    root.layout = Math.floor(Math.random() * root.layoutNames.length)
    root.buildTrack()
    root.score = 0
    root.coins = []
    root.sparks = []
    root.lastDot = ({})
    root.pops = []
    root.misses = []
    root.missCooldown = ({})
    root.highScoreEntry = null
    root.crashReason = ""
    root.crashCell = -1
    root.carLost = false
    root.coinsSinceCrash = 0
    root.cars = [{ cell: 0, from: root.eS, t: 0, variant: root.chosenCar, player: true }]
    root.obstacles = []
    root.spawnObstacles(root.spec.obstacles)
    root.cursor = Math.floor(root.rows / 2) * root.cols + Math.floor(root.cols / 2)
    for (var i = 0; i < root.coinsWanted; i++) root.spawnCoin()
    root.computeRoute()
    root.phase = "running"
  }

  function occupied(i) {
    for (var k = 0; k < root.cars.length; k++)
      if (root.cars[k].cell === i) return true
    return false
  }

  function coinAt(cell) {
    for (var i = 0; i < root.coins.length; i++)
      if (root.coins[i].cell === cell) return i
    return -1
  }

  function isObstacle(cell) {
    return root.obstacles.indexOf(cell) !== -1
  }

  // Every cell a car will reach if nobody touches anything: walk each car
  // forward until it repeats a (cell, entry edge) state. The board wraps now,
  // so this no longer needs an off-board exit to terminate — the (cell, from)
  // state space is finite regardless, and every car re-enters a state it has
  // already seen within four times the cell count at the latest.
  function reachableCells() {
    var cells = ({})
    for (var k = 0; k < root.cars.length; k++) {
      var states = ({})
      var c = root.cars[k].cell
      var f = root.cars[k].from
      for (var s = 0; s <= root.cellCount * 4; s++) {
        var st = c + ":" + f
        if (states[st]) break
        states[st] = true
        cells[c] = true
        var ex = root.exitFor(root.pieceOf(c), f)
        c = root.neighbor(c, ex)
        f = root.opp(ex)
      }
    }
    return cells
  }

  // Coins land only where the cars are *not* already going. Spawning uniformly
  // put more than half of them on the untouched rim loop, where they were
  // collected with no input at all: the game scored to 10 twice while nobody
  // was playing it. Excluding the live route makes every coin cost a reroute by
  // construction, which is the whole game rather than a timer.
  function spawnCoin() {
    var onRoute = root.reachableCells()
    var free = []
    var i
    for (i = 0; i < root.cellCount; i++)
      if (!onRoute[i] && root.coinAt(i) < 0 && !root.isObstacle(i) && !root.occupied(i)) free.push(i)
    // If the route has been bent until it covers the board, take anywhere legal
    // rather than starving the board of coins.
    if (free.length === 0)
      for (i = 0; i < root.cellCount; i++)
        if (root.coinAt(i) < 0 && !root.isObstacle(i) && !root.occupied(i)) free.push(i)
    if (free.length === 0) return
    var next = root.coins.slice()
    next.push({ cell: free[Math.floor(Math.random() * free.length)], born: Date.now() })
    root.coins = next
  }

  // Placed once at newGame(), on cells the opening loop doesn't already
  // reach — same reasoning as coins avoiding the live route, so a fresh
  // board never opens with a hazard already sitting on the one path there is.
  function spawnObstacles(count) {
    var onRoute = root.reachableCells()
    var free = []
    var i
    for (i = 0; i < root.cellCount; i++)
      if (!onRoute[i] && root.coinAt(i) < 0 && !root.isObstacle(i) && !root.occupied(i)) free.push(i)
    var next = root.obstacles.slice()
    for (var n = 0; n < count && free.length > 0; n++) {
      var pick = Math.floor(Math.random() * free.length)
      next.push(free[pick])
      free.splice(pick, 1)
    }
    root.obstacles = next
  }

  function dropCoin(i) {
    var next = root.coins.slice()
    next.splice(i, 1)
    root.coins = next
  }

  function collect(i) {
    var cell = root.coins[i].cell
    root.dropCoin(i)
    var p = root.pops.slice()
    p.push({ cell: cell, born: Date.now() })
    root.pops = p
    root.score += 1
    if (root.score > root.best) root.saveBest()

    if (root.carLost) {
      // A car down: the score ramp no longer decides this on its own, since
      // score keeps climbing regardless of a crash — a flat run of coins
      // earns the next car back instead, same as any other level's ramp,
      // just measured from the crash rather than from zero.
      root.coinsSinceCrash += 1
      if (root.coinsSinceCrash >= root.coinsForLife && root.cars.length < root.maxCars) {
        root.addCar()
        root.coinsSinceCrash = 0
        if (root.cars.length >= root.maxCars) root.carLost = false
      }
    } else if (root.cars.length < root.carCountFor(root.score)) {
      root.addCar()
    }
  }

  function saveBest() {
    var b = {}
    for (var k in root.bests) b[k] = root.bests[k]
    b[root.spec.key] = root.score
    root.bests = b
    root.writeState()
  }

  // Walk the route a car is already on and drop the new one half a lap behind
  // it. Anywhere else risks spawning onto a tile whose rails lead straight off
  // the board, which would be a crash the player never caused.
  function addCar() {
    if (root.cars.length === 0) return
    var lead = root.cars[0]
    var path = []
    var c = lead.cell, f = lead.from
    for (var s = 0; s < root.cellCount * 2; s++) {
      var ex = root.exitFor(root.pieceOf(c), f)
      c = root.neighbor(c, ex)
      f = root.opp(ex)
      if (c === lead.cell && f === lead.from) break
      path.push({ cell: c, from: f })
    }
    if (path.length < 4) return
    var pick = path[Math.floor(path.length / 2)]
    if (root.occupied(pick.cell)) return
    var player = !root.hasPlayer()
    var next = root.cars.slice()
    next.push({
      cell: pick.cell,
      from: pick.from,
      t: 0,
      variant: player ? root.chosenCar : root.nextTrafficVariant(),
      player: player
    })
    root.cars = next
    root.computeRoute()
  }

  // Returns true when the run is over (phase becomes "crashed"). A spare
  // car turns this into a lost life instead, and the tick must keep going
  // for the cars that are still on the board.
  function crash(cell, reason, car) {
    if (root.phase === "crashed") return true
    var idx = -1
    if (car)
      for (var k = 0; k < root.cars.length; k++)
        if (root.cars[k] === car) { idx = k; break }
    if (idx < 0)
      for (var k2 = 0; k2 < root.cars.length; k2++)
        if (root.cars[k2].cell === cell) { idx = k2; break }
    var c = idx >= 0 ? root.cars[idx] : car
    var p = c ? root.carPointOf(c, 1)
              : { x: (cell % root.cols) + 0.5, y: Math.floor(cell / root.cols) + 0.5 }
    root.crashPoint = { x: p.x, y: p.y }
    root.crashSeed = Math.random() * Math.PI * 2
    root.crashCell = cell
    root.crashPulse += 1

    if (root.cars.length > 1 && idx >= 0) {
      // A spare car left: lose the car, not the run. Drop the wake too —
      // spark entries were keyed by array index, so leaving them in place
      // recoloured the remaining cars' trails after the splice.
      var remaining = root.cars.slice()
      remaining.splice(idx, 1)
      root.cars = remaining
      root.sparks = []
      root.lastDot = ({})
      root.carLost = true
      root.coinsSinceCrash = 0
      root.computeRoute()
      return false
    }

    root.crashReason = reason
    root.phase = "crashed"
    if (root.score > root.best) root.saveBest()
    if (root.qualifiesForHighScore(root.score, root.spec.key))
      root.highScoreEntry = { text: "" }
    return true
  }

  // Turning a tile is the only move in the game, and the tile a car is
  // standing on is the one tile it costs you the run.
  // Bumped whenever a turn is refused, so the tile that refused it can say so.
  property int refuseSeq: 0
  property int refuseCell: -1
  // Same pattern as refuseSeq: a player-initiated turn, so tiles can pop
  // without also firing when newGame() rebuilds the board.
  property int turnSeq: 0
  property int turnCell: -1

  function rotate(cell) {
    if (root.phase !== "running") return
    if (cell < 0 || cell >= root.cellCount) return
    // Locked tiles refuse rather than kill. The occupied rule is the one that
    // costs you a run; welding a tile down is just geometry, and killing the
    // player for probing it would teach the wrong lesson.
    if (root.isLocked(cell)) {
      root.refuseCell = cell
      root.refuseSeq += 1
      return
    }
    if (root.occupied(cell)) {
      root.crash(cell, "you turned the track under a car")
      return
    }
    var next = root.turns.slice()
    next[cell] = next[cell] + 1
    root.turns = next
    root.turnCell = cell
    root.turnSeq += 1
    root.triggerFlash(cell)
    root.computeRoute()
  }

  // The route each car will take over the next few tiles. This is the whole
  // reason the game is readable: the two-flip move is invisible without it,
  // and the tile a bent route is about to run into is worth seeing before
  // the car gets there rather than after. The board no longer ends, so the
  // only way a route can be fatal now is an obstacle sitting in it.
  function computeRoute() {
    var out = []
    var look = root.spec.look
    for (var k = 0; k < root.cars.length; k++) {
      var c = root.cars[k].cell
      var f = root.cars[k].from
      for (var s = 0; s < look; s++) {
        var ex = root.exitFor(root.pieceOf(c), f)
        var nx = root.neighbor(c, ex)
        var hitsObstacle = root.isObstacle(nx)
        out.push({ cell: c, from: f, exit: ex, car: k, step: s, fatal: hitsObstacle })
        if (hitsObstacle) break
        c = nx
        f = root.opp(ex)
      }
    }
    root.route = out
  }

  // Hand a car to the next tile. The rails always meet and the board wraps,
  // so the only way this fails is the next tile being an obstacle.
  function advance(car) {
    var ex = root.exitFor(root.pieceOf(car.cell), car.from)
    var nxt = root.neighbor(car.cell, ex)
    if (root.isObstacle(nxt)) {
      root.crash(nxt, "hit an obstacle", car)
      return false
    }

    car.cell = nxt
    car.from = root.opp(ex)
    var ci = root.coinAt(nxt)
    if (ci >= 0) root.collect(ci)
    return true
  }

  function tick(dt) {
    var adv = dt * 1000 / root.tileTime
    var i
    var stepped = false

    // Snapshot the roster so a splice mid-loop cannot skip a living car, and
    // so a non-fatal wreck no longer aborts the rest of the frame.
    var roster = root.cars.slice()
    for (i = 0; i < roster.length; i++) {
      var car = roster[i]
      if (root.cars.indexOf(car) < 0) continue
      car.t += adv
      var guard = 0
      while (car.t >= 1 && guard++ < 8) {
        car.t -= 1
        stepped = true
        if (!root.advance(car)) {
          if (root.phase === "crashed") {
            root.frame++
            return
          }
          break
        }
        if (root.cars.indexOf(car) < 0) break
      }
    }

    // Same tile is not enough on its own: two cars can share a tile a third of
    // a tile apart and that should read as a near miss, not a wreck. A little
    // further out than the crash radius, it is a near miss instead of a wreck,
    // and worth a flash of its own — the traffic ramp exists so these keep
    // happening, and a game that only ever announces its failure mode reads
    // as tenser than it is.
    var now = Date.now()
    var missAdded = false
    var mc = root.missCooldown
    var collided = false
    for (i = 0; i < root.cars.length && !collided; i++) {
      for (var j = i + 1; j < root.cars.length; j++) {
        if (root.cars[i].cell !== root.cars[j].cell) continue
        var a = root.carState(i, 1)
        var b = root.carState(j, 1)
        var dx = a.x - b.x, dy = a.y - b.y
        var d = Math.sqrt(dx * dx + dy * dy)
        if (d < 0.30) {
          root.crash(root.cars[i].cell, "two cars, one tile", root.cars[i])
          collided = true
          if (root.phase === "crashed") {
            root.frame++
            return
          }
          break
        }
        if (d < 0.62) {
          var pk = i + ":" + j
          if (now - (mc[pk] || 0) > 900) {
            if (!missAdded) { mc = Object.assign({}, mc); missAdded = true }
            mc[pk] = now
            var m = root.misses.slice()
            m.push({ x: (a.x + b.x) / 2, y: (a.y + b.y) / 2, born: now })
            root.misses = m
          }
        }
      }
    }
    if (missAdded) root.missCooldown = mc

    var added = false
    var sp = root.sparks
    for (i = 0; i < root.cars.length; i++) {
      var pt = root.carPointOf(root.cars[i], 1)
      var qx = Math.round(pt.x * root.dotStep) / root.dotStep
      var qy = Math.round(pt.y * root.dotStep) / root.dotStep
      var key = qx + ":" + qy
      if (root.lastDot[i] === key) continue
      root.lastDot[i] = key
      if (!added) { sp = root.sparks.slice(); added = true }
      sp.push({ x: qx, y: qy, hue: root.variantFor(i) })
    }
    if (added) {
      var cap = Math.max(1, root.cars.length) * root.sparksPerCar
      while (sp.length > cap) sp.shift()
      root.sparks = sp
    }

    for (i = root.coins.length - 1; i >= 0; i--)
      if (now - root.coins[i].born > root.coinLife) root.dropCoin(i)
    while (root.coins.length < root.coinsWanted) root.spawnCoin()

    if (root.pops.length > 0) {
      var alive = []
      for (i = 0; i < root.pops.length; i++)
        if (now - root.pops[i].born < root.popLife) alive.push(root.pops[i])
      if (alive.length !== root.pops.length) root.pops = alive
    }

    if (root.misses.length > 0) {
      var aliveMisses = []
      for (i = 0; i < root.misses.length; i++)
        if (now - root.misses[i].born < root.missLife) aliveMisses.push(root.misses[i])
      if (aliveMisses.length !== root.misses.length) root.misses = aliveMisses
    }

    if (stepped) root.computeRoute()
    root.frame++
  }

  // Position and heading of a car, in units of `cell` pixels from the board's
  // top-left. Pass cell = 1 for unit coordinates.
  function carState(i, cell) { return root.carPointOf(root.cars[i], cell) }

  function carPointOf(car, cell) {
    if (!car) return { x: 0, y: 0, angle: 0 }
    var ex = root.exitFor(root.pieceOf(car.cell), car.from)
    var a = root.edgeMid(car.from)
    var b = root.edgeMid(ex)
    var t = Math.max(0, Math.min(1, car.t))
    var u = 1 - t

    var px = u * u * a.x + 2 * u * t * 0.5 + t * t * b.x
    var py = u * u * a.y + 2 * u * t * 0.5 + t * t * b.y
    var dx = 2 * u * (0.5 - a.x) + 2 * t * (b.x - 0.5)
    var dy = 2 * u * (0.5 - a.y) + 2 * t * (b.y - 0.5)

    var cx = car.cell % root.cols
    var cy = Math.floor(car.cell / root.cols)
    return {
      x: (cx + px) * cell,
      y: (cy + py) * cell,
      angle: Math.atan2(dy, dx) * 180 / Math.PI
    }
  }

  FrameAnimation {
    // `helpOpen` doesn't touch `phase` (closing it should resume exactly
    // where play left off), but leaving the tick running underneath it
    // meant the whole board — cars, trail, coin timers — kept moving behind
    // a translucent scrim while you were trying to read: distracting at
    // best, and the fuse timers no reader agreed to keep burning.
    running: root.opened && root.phase === "running" && !root.helpOpen && !root.menuOpen
    // A frame lost to a stall should not teleport a car through three tiles.
    onTriggered: root.tick(Math.min(0.05, frameTime))
  }

  // ------------------------------------------------------------------ state

  // The real asset off the installed tree rather than a redrawn copy, so the
  // mark on the coin is always the one this machine's Omarchy ships.
  //
  // Not named `omarchyPath`: the shell host injects a property of that name
  // into a plugin root the way it injects `shell`, and declaring it here as
  // readonly makes the assignment throw, which takes the whole panel down with
  // it. The failure is silent apart from one TypeError in the shell log.
  readonly property string omaRoot: Quickshell.env("OMARCHY_PATH") || "/usr/share/omarchy"
  readonly property string omarchyIcon: "file://" + root.omaRoot + "/icon.png"

  // Scores live under XDG state, never under ~/.config. HOME must be a real
  // absolute path: an empty HOME would otherwise mkdir -p /.local/state/...
  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string stateDir: (root.home.charAt(0) === "/" && root.home.indexOf("..") === -1)
    ? root.home + "/.local/state/omacircuit" : ""
  readonly property string statePath: root.stateDir !== "" ? root.stateDir + "/state.json" : ""
  property bool stateLoaded: false

  function clampInt(n, lo, hi, fallback) {
    n = Number(n)
    if (!isFinite(n)) return fallback
    n = Math.floor(n)
    return Math.max(lo, Math.min(hi, n))
  }

  // High-score names are typed as printable ASCII, 8 chars. Re-apply the
  // same rule when reading state.json so a hand-edited file cannot inject
  // control characters into the Text items that display them.
  function sanitizeName(s) {
    s = String(s || "")
    var out = ""
    for (var i = 0; i < s.length && out.length < 8; i++) {
      var ch = s.charAt(i)
      if (ch >= " " && ch <= "~") out += ch
    }
    return out
  }

  function applyState(raw) {
    var wantLevel = root.level
    try {
      var s = JSON.parse(String(raw || ""))
      if (s && typeof s === "object") {
        var b = {}
        if (s.bests && typeof s.bests === "object") {
          for (var i = 0; i < root.levels.length; i++) {
            var key = root.levels[i].key
            if (typeof s.bests[key] === "number")
              b[key] = root.clampInt(s.bests[key], 0, 99999, 0)
          }
        } else if (typeof s.best === "number") {
          b.circuit = root.clampInt(s.best, 0, 99999, 0)  // v1
        }
        root.bests = b

        var hs = {}
        if (s.highScores && typeof s.highScores === "object") {
          for (var j = 0; j < root.levels.length; j++) {
            var hk = root.levels[j].key
            var list = s.highScores[hk]
            if (!Array.isArray(list)) continue
            var clean = []
            for (var n = 0; n < list.length && clean.length < 5; n++) {
              var row = list[n]
              if (!row || typeof row !== "object") continue
              var name = root.sanitizeName(row.name).trim()
              var score = root.clampInt(row.score, 1, 99999, 0)
              if (name !== "" && score > 0) clean.push({ name: name, score: score })
            }
            clean.sort(function(a, b) { return b.score - a.score })
            if (clean.length > 0) hs[hk] = clean
          }
        }
        root.highScores = hs

        if (typeof s.level === "number") wantLevel = s.level
        if (typeof s.chosenCar === "number")
          root.chosenCar = root.clampInt(s.chosenCar, 0, 2, 0)
      }
    } catch (e) {
    }
    root.stateLoaded = true
    root.level = Math.max(0, Math.min(root.levels.length - 1, wantLevel))
    root.newGame()
  }

  function writeState() {
    if (!root.stateLoaded || root.statePath === "") return
    stateFile.setText(JSON.stringify({
      version: 3,
      bests: root.bests,
      highScores: root.highScores,
      level: root.level,
      chosenCar: root.chosenCar
    }))
  }

  FileView {
    id: stateFile
    path: root.statePath
    atomicWrites: true
    printErrors: false
    onLoaded: root.applyState(text())
    onLoadFailed: function(err) { root.applyState("") }
  }

  Process {
    id: mkStateDir
    command: ["mkdir", "-p", "--", root.stateDir]
    onExited: stateFile.reload()
  }

  Component.onCompleted: {
    if (root.stateDir !== "") mkStateDir.running = true
    else root.applyState("")
    root.newGame()
    // Deferred a tick so this is a real false->true transition the
    // overlay's onVisibleChanged can react to, rather than folded into the
    // same construction pass as its own initial (already-false) value.
    Qt.callLater(function() { root.menuOpen = true })
  }

  // ------------------------------------------------------------- open/close

  function open(payloadJson) {
    root.opened = true
    // A wreck you already read is not worth coming back to.
    if (root.phase === "crashed") root.newGame()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    if (!root.opened) return
    root.opened = false
    root.helpOpen = false
    if (root.phase === "running") root.phase = "paused"
    root.writeState()
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide(root.selfId)
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open("{}")
  }

  function handleKey(event) {
    var key = event.key

    // The start menu owns the keyboard outright while it's up too, for the
    // same reason name entry does: q/space/arrows all mean something else
    // everywhere else in this function.
    if (root.menuOpen) {
      if (key === Qt.Key_Escape || key === Qt.Key_Q) { root.close(); return true }
      if (key === Qt.Key_Left || key === Qt.Key_A || key === Qt.Key_H) {
        root.setChosenCar((root.chosenCar + 2) % 3)
        return true
      }
      if (key === Qt.Key_Right || key === Qt.Key_D || key === Qt.Key_L) {
        root.setChosenCar((root.chosenCar + 1) % 3)
        return true
      }
      if (key === Qt.Key_Space || key === Qt.Key_Return || key === Qt.Key_Enter) {
        root.menuOpen = false
        return true
      }
      return true
    }

    // Name entry owns the keyboard outright while it's up, and has to be
    // checked before anything else — including Escape/Q, below, which
    // normally closes the panel. Letters like Q, R, P, H, J, K, L double as
    // shortcuts everywhere else in this function, and a name is allowed to
    // contain any of them, so this has to intercept before those bindings
    // ever see the keystroke.
    if (root.highScoreEntry) {
      var e = root.highScoreEntry
      if (key === Qt.Key_Escape) { root.highScoreEntry = null; return true }
      if (key === Qt.Key_Backspace) {
        root.highScoreEntry = { text: e.text.slice(0, -1) }
        return true
      }
      if (key === Qt.Key_Return || key === Qt.Key_Enter) {
        if (e.text.trim().length > 0) root.commitHighScore()
        return true
      }
      // Anything else that produced actual text — this is what lets Space
      // type a space rather than doing its usual job, and is also why a
      // bare modifier key or an arrow (which produce no text) falls through
      // to nothing instead of inserting a stray character.
      var ch = event.text
      if (ch && ch.length === 1 && ch >= " " && ch <= "~" && e.text.length < 8)
        root.highScoreEntry = { text: root.sanitizeName(e.text + ch) }
      return true
    }

    if (key === Qt.Key_Escape || key === Qt.Key_Q) { root.close(); return true }
    if (key === Qt.Key_R) { root.newGame(); return true }
    if (key === Qt.Key_Question || key === Qt.Key_Slash) {
      root.helpOpen = !root.helpOpen
      return true
    }
    if (key === Qt.Key_1) { root.setLevel(0); return true }
    if (key === Qt.Key_2) { root.setLevel(1); return true }
    if (key === Qt.Key_3) { root.setLevel(2); return true }
    if (key === Qt.Key_4) { root.setLevel(3); return true }
    if (key === Qt.Key_P) {
      if (root.phase !== "crashed")
        root.phase = (root.phase === "paused") ? "running" : "paused"
      return true
    }

    if (key === Qt.Key_Left  || key === Qt.Key_H) { root.moveCursor(-1, 0); return true }
    if (key === Qt.Key_Right || key === Qt.Key_L) { root.moveCursor(1, 0);  return true }
    if (key === Qt.Key_Up    || key === Qt.Key_K) { root.moveCursor(0, -1); return true }
    if (key === Qt.Key_Down  || key === Qt.Key_J) { root.moveCursor(0, 1);  return true }

    // Space is the move while you are playing and the dismiss while you are
    // looking at an overlay, which is the only reading of it that is never
    // ambiguous on screen.
    if (key === Qt.Key_Space || key === Qt.Key_Return || key === Qt.Key_Enter) {
      if (root.helpOpen) root.helpOpen = false
      else if (root.phase === "crashed") root.newGame()
      else if (root.phase === "paused") root.phase = "running"
      else root.rotate(root.cursor)
      return true
    }
    return false
  }

  // ----------------------------------------------------------------- window

  readonly property int preferredCell: Style.space(58)
  readonly property int chromeHeight: Style.space(30) + Style.space(22) + Style.space(26)
                                      + Style.spacing.panelGap * 2 + Style.spacing.md

  FloatingWindow {
    id: win
    visible: root.opened
    title: "omacircuit"
    color: root.background

    implicitWidth: root.cols * root.preferredCell + root.contentMargin * 2
    implicitHeight: root.rows * root.preferredCell + root.contentMargin * 2 + root.chromeHeight
    minimumSize: Qt.size(root.cols * Style.space(24) + root.contentMargin * 2,
                         root.rows * Style.space(24) + root.contentMargin * 2 + root.chromeHeight)

    // Closing from the compositor is closing the game: the host still thinks
    // the panel is open otherwise, and the next toggle would do nothing.
    onClosed: root.close()

    Item {
      id: keyCatcher
      anchors.fill: parent
      anchors.margins: root.contentMargin
      focus: true

      Keys.onPressed: function(event) {
        if (root.handleKey(event)) event.accepted = true
      }

      // ----------------------------------------------------------- header
      Item {
        id: header
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: Math.max(title.implicitHeight, levelPicker.implicitHeight)

        Row {
          id: title
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.spacing.sm

          Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(2, Math.round(Style.font.title * 0.25))
            height: Math.round(Style.font.title * 1.1)
            color: root.levelColor
          }
          // A terminal prompt rather than a plain wordmark: `$` in the
          // level's own color, the name, then a block cursor that blinks
          // on its own clock. Small touch, but it is what stops a static
          // heading from reading like a label and starts it reading like
          // something waiting on you.
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "$ "
            color: root.levelColor
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "omacircuit"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
          }
          Rectangle {
            id: titleCursor
            anchors.verticalCenter: parent.verticalCenter
            width: Math.round(Style.font.title * 0.55)
            height: Math.round(Style.font.title * 0.95)
            color: root.foreground

            SequentialAnimation on opacity {
              loops: Animation.Infinite
              NumberAnimation { to: 0; duration: 20; easing.type: Easing.OutQuad }
              PauseAnimation { duration: 480 }
              NumberAnimation { to: 1; duration: 20 }
              PauseAnimation { duration: 480 }
            }
          }

          Item { width: Style.spacing.lg; height: 1 }

          // The live count, "above" the board rather than only under it —
          // the same shared Coin component the readout under the board and
          // the wrecked-card header use, just smaller.
          Coin {
            anchors.verticalCenter: parent.verticalCenter
            cell: Math.round(Style.font.title * 1.1)
            hud: true
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.score
            color: root.coinColor
            font.family: root.fontFamily
            font.pixelSize: Style.font.subtitle
            font.bold: true
          }

          Item { width: Style.spacing.lg; height: 1 }

          // A life per car this level can field, so "you have three lives"
          // is something you can see rather than only discover by surviving
          // a wreck — filled in that car's own hue while it's alive, hollow
          // once it's gone. The next hollow dot in line fills in with the
          // coin color as coinsSinceCrash climbs toward earning it back.
          Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.spacing.xxs
            visible: root.maxCars > 1

            Repeater {
              model: root.maxCars

              Rectangle {
                readonly property bool alive: index < root.cars.length
                readonly property bool recovering: !alive && root.carLost && index === root.cars.length
                width: Math.round(Style.font.subtitle * 0.55)
                height: width
                radius: width / 2
                color: alive ? root.carColor(index)
                       : recovering ? root.fade(root.coinColor, 0.25 + 0.65 * Math.min(1, root.coinsSinceCrash / root.coinsForLife))
                       : "transparent"
                border.width: Math.max(1, Style.space(2))
                border.color: alive ? root.core(root.carColor(index))
                                    : root.fade(root.foreground, 0.35)
              }
            }
          }
        }

        // Name on the left, controls on the right: crammed together they left
        // the whole right half of the header empty.
        //
        // The level picker doubles as the level readout, so there is one place
        // to look and one place to click.
        Row {
          id: levelPicker
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.spacing.xs

          Repeater {
            model: root.levels.length

            Rectangle {
              readonly property bool current: root.level === index
              width: chip.implicitWidth + Style.spacing.md * 2
              height: chip.implicitHeight + Style.spacing.xs * 2
              radius: height / 2
              color: current ? root.fade(root.levelHues[index], 0.20) : "transparent"
              border.width: 1
              border.color: current ? root.levelHues[index]
                                    : root.fade(root.gridNeon, 0.35)

              Text {
                id: chip
                anchors.centerIn: parent
                text: root.levels[index].name
                color: parent.current ? root.levelHues[index] : root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: parent.current
              }

              TapHandler { onTapped: root.setLevel(index) }
            }
          }
        }
      }

      // ------------------------------------------------------------ leaders
      //
      // The wrecked card already showed this level's top five, but only
      // after a wreck — asked to have it up during play too, not just as a
      // post-mortem. Kept to three entries and one line rather than
      // reproducing the card's full five-row list: this sits above the
      // board permanently, so it has to stay out of the way of the thing
      // it's next to.
      Row {
        id: liveBoard
        anchors.top: header.bottom
        anchors.topMargin: Style.spacing.xs
        anchors.horizontalCenter: parent.horizontalCenter
        visible: (root.highScores[root.spec.key] || []).length > 0
        spacing: Style.spacing.lg

        Repeater {
          model: (root.highScores[root.spec.key] || []).slice(0, 3)

          Row {
            required property var modelData
            required property int index
            spacing: Style.spacing.xxs

            Medal {
              rank: index + 1
              width: Style.space(26)
              height: width
              anchors.verticalCenter: parent.verticalCenter
            }
            Text {
              text: modelData.name || "—"
              textFormat: Text.PlainText
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              anchors.verticalCenter: parent.verticalCenter
            }
            Text {
              text: modelData.score
              color: root.coinColor
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              anchors.verticalCenter: parent.verticalCenter
            }
          }
        }
      }

      // ------------------------------------------------------------ board
      Item {
        id: boardSlot
        anchors.top: liveBoard.visible ? liveBoard.bottom : header.bottom
        anchors.topMargin: Style.spacing.panelGap
        anchors.bottom: statusLine.top
        anchors.bottomMargin: Style.spacing.panelGap
        anchors.left: parent.left
        anchors.right: parent.right

        readonly property int pad: Style.space(7)
        // The readout's height does not depend on the cell size, so taking it
        // out of the budget here cannot feed back into it.
        readonly property int readoutH: Math.round(Style.font.subtitle * 2.3)
        readonly property int cell: Math.max(8, Math.floor(Math.min(
          (width - pad * 2) / root.cols,
          (height - pad * 2 - readoutH - Style.spacing.md) / root.rows)))

        Column {
          anchors.centerIn: parent
          spacing: Style.spacing.md
        Rectangle {
          id: boardFrame
          // Sized to the board rather than to the space available. Filling the
          // slot left a tall empty rectangle above and below the play area,
          // which read as unfinished layout rather than as margin.
          width: boardSlot.cell * root.cols + boardSlot.pad * 2
          height: boardSlot.cell * root.rows + boardSlot.pad * 2
          color: root.boardBg
          radius: root.cornerRadius
          // A hairline and nothing else. Two heavy rings around a board that
          // already has corner brackets was weight for its own sake.
          border.width: 1
          border.color: root.fade(root.gridNeon, 0.28)

          // Four corner brackets in the level's color. The frame was a plain
          // rounded rectangle; the brackets are what make it read as a rig the
          // board is mounted in rather than as a border around it.
          Repeater {
            model: 4

            Item {
              readonly property bool atRight: index % 2 === 1
              readonly property bool atBottom: index > 1
              readonly property int arm: Math.max(6, Math.round(boardSlot.cell * 0.55))
              readonly property int thick: Math.max(1, Style.space(2))

              width: arm
              height: arm
              x: atRight ? boardFrame.width - arm : 0
              y: atBottom ? boardFrame.height - arm : 0

              Rectangle {
                width: parent.arm
                height: parent.thick
                y: parent.atBottom ? parent.arm - height : 0
                color: root.fade(root.levelColor, 0.55)
              }
              Rectangle {
                width: parent.thick
                height: parent.arm
                x: parent.atRight ? parent.arm - width : 0
                color: root.fade(root.levelColor, 0.55)
              }
            }
          }

          Item {
            id: boardArea
            readonly property int cell: boardSlot.cell
            width: cell * root.cols
            height: cell * root.rows
            anchors.centerIn: parent
            clip: true

            // The wreck used to be a state change and a fade. A short shake
            // costs one transform and is most of what sells the impact.
            transform: Translate { id: boardShake }

            // Set for a moment on a wreck that only cost a car — phase never
            // leaves "running" then, so the debris burst below needs its own
            // trigger instead of riding the phase change the game-over one uses.
            property bool wreckFlash: false

            Connections {
              target: root
              function onCrashPulseChanged() {
                shakeAnim.restart()
                flashAnim.restart()
                if (root.phase !== "crashed") {
                  boardArea.wreckFlash = true
                  wreckFlashTimer.restart()
                }
              }
            }

            Timer { id: wreckFlashTimer; interval: 650; onTriggered: boardArea.wreckFlash = false }

            SequentialAnimation {
              id: shakeAnim
              NumberAnimation { target: boardShake; property: "x"; to:  10; duration: 45 }
              NumberAnimation { target: boardShake; property: "x"; to:  -8; duration: 55 }
              NumberAnimation { target: boardShake; property: "y"; to:   6; duration: 45 }
              NumberAnimation { target: boardShake; property: "x"; to:   5; duration: 45 }
              NumberAnimation { target: boardShake; property: "y"; to:  -3; duration: 45 }
              ParallelAnimation {
                NumberAnimation { target: boardShake; property: "x"; to: 0; duration: 70; easing.type: Easing.OutQuad }
                NumberAnimation { target: boardShake; property: "y"; to: 0; duration: 70; easing.type: Easing.OutQuad }
              }
            }

            // ---- the grid, as a dot field rather than a lattice of boxes.
            // One dot per tile corner keeps the structure legible while giving
            // the board its ground back for the rails and the traffic.
            Repeater {
              model: (root.cols + 1) * (root.rows + 1)

              Rectangle {
                id: gridDot
                readonly property int gx: index % (root.cols + 1)
                readonly property int gy: Math.floor(index / (root.cols + 1))
                readonly property bool edge: gx === 0 || gy === 0
                                          || gx === root.cols || gy === root.rows
                readonly property real base: edge ? 0.55 : 0.28
                // A traveling wave rather than per-dot random twinkling —
                // "dot matrix" implies these are particles, not a drawn grid,
                // and a field of Rectangles that never moves reads as drawn
                // no matter how small the dots are. Sampling the shared
                // `root.wavePhase` clock with a phase offset built from this
                // dot's own board position is what gives the twinkle a
                // direction: brightness sweeps diagonally across the whole
                // field instead of every dot flickering independently.
                readonly property real twinkle: 1.1 + 0.6 * Math.sin(root.wavePhase - (gx + gy) * 0.5)

                width: Math.max(1, Math.round(boardArea.cell * (edge ? 0.050 : 0.038)))
                height: width
                radius: width / 2
                x: gx * boardArea.cell - width / 2
                y: gy * boardArea.cell - height / 2
                color: root.dotNeon
                opacity: gridDot.base * gridDot.twinkle
              }
            }

            // ---- tiles
            Repeater {
              model: root.cellCount

              Item {
                id: tile
                readonly property int cell: boardArea.cell
                readonly property int piece: root.pieceOf(index)
                readonly property var paths: root.pathsFor(piece)
                readonly property bool locked: (root.frame, root.occupied(index))
                readonly property bool welded: root.isLocked(index)
                readonly property bool wrecked: root.phase === "crashed" && root.crashCell === index
                // Reads the one shared flash instead of keeping its own —
                // see `root.flashCell`/`flashAmount` above.
                readonly property real turnFlash: index === root.flashCell ? root.flashAmount : 0

                x: (index % root.cols) * cell
                y: Math.floor(index / root.cols) * cell
                width: cell
                height: cell

                // No fill follows the car any more. A red box tracking the car
                // around the board was the loudest thing on screen and it was
                // saying something the cursor already says: the cursor turns red
                // when it is standing on a car, which is the only moment the
                // occupied rule can actually cost you anything.
                Rectangle {
                  anchors.fill: parent
                  color: tile.wrecked ? root.fade(root.dangerColor, 0.22)
                       : tile.welded ? root.weldBed
                       : hover.hovered && root.phase === "running" ? root.hoverFill
                       : "transparent"
                  // No box around every tile. Forty-eight outlined squares
                  // read as a spreadsheet; the dot field below carries the
                  // same grid for a fraction of the ink, and only states that
                  // need an edge still draw one.
                  border.width: tile.wrecked || tile.welded ? 1 : 0
                  border.color: tile.wrecked ? root.lockedLine
                                             : root.fade(root.weldColor, 0.55)
                  Behavior on color { ColorAnimation { duration: 90 } }
                }

                Shape {
                  id: rails
                  anchors.fill: parent
                  preferredRendererType: Shape.CurveRenderer

                  // Ballast under each rail, for a little depth at no cost.
                  ShapePath {
                    strokeWidth: tile.cell * 0.20
                    strokeColor: root.conduit
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    startX: root.edgeMid(tile.paths[0][0]).x * tile.cell
                    startY: root.edgeMid(tile.paths[0][0]).y * tile.cell
                    PathQuad {
                      x: root.edgeMid(tile.paths[0][1]).x * tile.cell
                      y: root.edgeMid(tile.paths[0][1]).y * tile.cell
                      controlX: tile.cell * 0.5
                      controlY: tile.cell * 0.5
                    }
                  }
                  ShapePath {
                    strokeWidth: tile.cell * 0.20
                    strokeColor: root.conduit
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    startX: root.edgeMid(tile.paths[1][0]).x * tile.cell
                    startY: root.edgeMid(tile.paths[1][0]).y * tile.cell
                    PathQuad {
                      x: root.edgeMid(tile.paths[1][1]).x * tile.cell
                      y: root.edgeMid(tile.paths[1][1]).y * tile.cell
                      controlX: tile.cell * 0.5
                      controlY: tile.cell * 0.5
                    }
                  }
                  // Welded track only: a solid stroke, because a locked
                  // tile is meant to read as fixed metal. Unwelded track is
                  // drawn once for the whole board by `trackField` (a single
                  // Canvas, below, outside this per-tile Repeater) rather
                  // than here — see the comment there for why per-tile
                  // rendering of this could not be made cheap at any dot
                  // count or redraw rate that was tried.
                  ShapePath {
                    strokeWidth: Math.max(1, tile.cell * 0.060)
                    strokeColor: tile.welded ? root.weldColor : "transparent"
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    startX: root.edgeMid(tile.paths[0][0]).x * tile.cell
                    startY: root.edgeMid(tile.paths[0][0]).y * tile.cell
                    PathQuad {
                      x: root.edgeMid(tile.paths[0][1]).x * tile.cell
                      y: root.edgeMid(tile.paths[0][1]).y * tile.cell
                      controlX: tile.cell * 0.5
                      controlY: tile.cell * 0.5
                    }
                  }
                  ShapePath {
                    strokeWidth: Math.max(1, tile.cell * 0.060)
                    strokeColor: tile.welded ? root.weldColor : "transparent"
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    startX: root.edgeMid(tile.paths[1][0]).x * tile.cell
                    startY: root.edgeMid(tile.paths[1][0]).y * tile.cell
                    PathQuad {
                      x: root.edgeMid(tile.paths[1][1]).x * tile.cell
                      y: root.edgeMid(tile.paths[1][1]).y * tile.cell
                      controlX: tile.cell * 0.5
                      controlY: tile.cell * 0.5
                    }
                  }
                }


                // A click changes the shape rather than the angle, so the
                // feedback is a pop rather than a turn. Driven off turnSeq
                // rather than onPieceChanged, which also fired for every
                // tile newGame() rewrote.
                Connections {
                  target: root
                  function onTurnSeqChanged() {
                    if (root.turnCell === index) { pop.restart(); shock.restart() }
                  }
                }
                SequentialAnimation {
                  id: pop
                  NumberAnimation { target: rails; property: "scale"; to: 0.84; duration: 60; easing.type: Easing.OutQuad }
                  NumberAnimation { target: rails; property: "scale"; to: 1.0;  duration: 130; easing.type: Easing.OutBack }
                }

                // The literal "outbound" read: a ring launched from the
                // tile's own center outward past its edges, in the rail's
                // hue, so a turn announces itself beyond the one tile it
                // changed rather than only inside it.
                Rectangle {
                  id: shockRing
                  anchors.centerIn: parent
                  width: tile.cell * 0.30
                  height: width
                  radius: width / 2
                  color: "transparent"
                  border.width: Math.max(2, tile.cell * 0.045)
                  border.color: root.railNeon
                  opacity: 0
                }
                SequentialAnimation {
                  id: shock
                  ScriptAction { script: { shockRing.width = tile.cell * 0.30; shockRing.opacity = 0.85 } }
                  ParallelAnimation {
                    NumberAnimation { target: shockRing; property: "width"; to: tile.cell * 1.35; duration: 380; easing.type: Easing.OutQuad }
                    NumberAnimation { target: shockRing; property: "opacity"; to: 0; duration: 380; easing.type: Easing.OutQuad }
                  }
                }

                // The keyboard cursor, drawn as a bracket rather than a fill so
                // it never hides the rails it is pointing at.
                Rectangle {
                  anchors.fill: parent
                  anchors.margins: Math.max(1, tile.cell * 0.05)
                  visible: root.cursor === index
                  color: root.fade(tile.locked ? root.dangerColor : root.cursorColor, 0.16)
                  radius: Math.max(2, tile.cell * 0.12)
                  border.width: Math.max(2, Math.round(tile.cell * 0.06))
                  // The one place the occupied rule still shows itself, and the
                  // only place it matters: this is the tile a click would turn.
                  border.color: tile.locked ? root.dangerColor : root.cursorColor
                }

                // A welded tile says no by flinching, which is unmistakable and
                // costs nothing on every frame it is not happening.
                transform: Translate { id: refuseNudge }
                Connections {
                  target: root
                  function onRefuseSeqChanged() {
                    if (root.refuseCell === index) refuseAnim.restart()
                  }
                }
                SequentialAnimation {
                  id: refuseAnim
                  NumberAnimation { target: refuseNudge; property: "x"; to:  Math.max(2, tile.cell * 0.05); duration: 45 }
                  NumberAnimation { target: refuseNudge; property: "x"; to: -Math.max(2, tile.cell * 0.04); duration: 55 }
                  NumberAnimation { target: refuseNudge; property: "x"; to: 0; duration: 60; easing.type: Easing.OutQuad }
                }

                HoverHandler { id: hover; enabled: !tile.welded }
                TapHandler {
                  acceptedButtons: Qt.LeftButton
                  // Clicking also parks the cursor, so the two ways of playing
                  // never disagree about where you are.
                  onTapped: { root.cursor = index; root.rotate(index) }
                }
              }
            }

            // ---- idle track, as one dot-matrix field for the whole board.
            //
            // This is the third attempt at making the idle track read as
            // particles rather than a drawn line, and the one that actually
            // works at speed. The first two both rendered the dots per
            // *tile* — up to 70 separate Items, or later 70 separate
            // Canvas elements, one paint() each — and both measured at
            // roughly half of this plugin's entire CPU cost, no matter the
            // dot count or redraw throttling. Hiding 70 *empty, non-
            // repainting* Canvas items still cost most of that, which is
            // what gave away the actual problem: it was never the dots, the
            // wave, or the redraw rate, it was having 70 of *anything* with
            // its own scene-graph presence. One Canvas for the whole board,
            // looping over every tile inside a single paint() call, pays
            // that fixed per-item cost exactly once instead of seventy
            // times, for the same pixels on screen.
            //
            // `repaintDep` exists purely so reassigning it (a new array is
            // never `===` the old one) fires `onRepaintDepChanged`, since a
            // Canvas does not auto-track what its own onPaint reads the way
            // an Item's property bindings would.
            Canvas {
              id: trackField
              anchors.fill: parent
              readonly property int dotsPerPath: 6
              property var repaintDep: [root.turns, root.flashCell, root.flashAmount, boardArea.cell]
              onRepaintDepChanged: requestPaint()
              onPaint: {
                var ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)
                var cell = boardArea.cell
                var r = cell * 0.019
                for (var idx = 0; idx < root.cellCount; idx++) {
                  if (root.isLocked(idx)) continue
                  var flash = idx === root.flashCell ? root.flashAmount : 0
                  var piece = root.pieceOf(idx)
                  // A tile that has been turned stays green at rest instead
                  // of fading back to the idle blue every other crossing
                  // uses — the shape of the bend was already there to read,
                  // but it took parsing dot geometry at a glance to see it;
                  // the color now says "this one's been turned" for free.
                  var base = piece === 0 ? root.railIdle : root.railNeon
                  ctx.fillStyle = root.core(root.mix(base, root.core(root.railNeon), flash))
                  var paths = root.pathsFor(piece)
                  var tx = (idx % root.cols) * cell
                  var ty = Math.floor(idx / root.cols) * cell
                  for (var p = 0; p < 2; p++) {
                    var a = root.edgeMid(paths[p][0])
                    var b = root.edgeMid(paths[p][1])
                    for (var i = 0; i < dotsPerPath; i++) {
                      var t = (i + 0.5) / dotsPerPath
                      var pt = root.quadPoint(a, { x: 0.5, y: 0.5 }, b, t)
                      ctx.globalAlpha = Math.max(0, Math.min(1, 0.72 + 0.28 * flash))
                      ctx.beginPath()
                      ctx.arc(tx + pt.x * cell, ty + pt.y * cell, r, 0, Math.PI * 2)
                      ctx.fill()
                    }
                  }
                }
              }
            }

            // ---- spark wake
            Repeater {
              model: root.sparks.length

              Rectangle {
                id: spark
                readonly property var sp: root.sparks[index]
                // Oldest at the front of the array, so position in it is age.
                readonly property real life: (index + 1) / Math.max(1, root.sparks.length)
                readonly property color tint: {
                  var h = sp && typeof sp.hue === "number" ? sp.hue
                        : (sp && typeof sp.car === "number" ? root.variantFor(sp.car) : 0)
                  return root.carHues[h % root.carHues.length]
                }

                // A glitter pass on top of the age-based fade, not instead of
                // it: age still says how old the dot is, this just says
                // whether it caught the light this instant. Cheap on
                // purpose — a hash of the dot's index and a coarse time
                // bucket, both already-cheap numbers, rather than a
                // per-dot Timer or Animator. `root.frame` already ticks every
                // frame for the game loop regardless, so this rides that
                // clock for free instead of starting a new one; bucketing it
                // by 8 frames (~130ms) is what keeps a flash on screen long
                // enough to read as a glint rather than a single-frame flicker
                // too fast to see. `sparksPerCar` is at most 138 across three
                // cars — small enough that a per-dot binding like this is not
                // the kind of item-count problem the idle track dots were.
                readonly property real glitterSeed: {
                  var bucket = Math.floor(root.frame / 8)
                  var h = Math.sin((index + 1) * 12.9898 + bucket * 78.233) * 43758.5453
                  return h - Math.floor(h)
                }
                readonly property bool glittering: life > 0.35 && glitterSeed > 0.92

                visible: !!sp
                // Uniform and tiny. A dot matrix reads as a matrix because the
                // dots are all the same size; age is carried by brightness alone,
                // and dropping the per-dot halo is what pays for having this many.
                width: Math.max(1, Math.round(boardArea.cell * 0.055))
                height: width
                radius: width / 2
                x: (sp ? sp.x : 0) * boardArea.cell - width / 2
                y: (sp ? sp.y : 0) * boardArea.cell - height / 2
                color: glittering ? "#ffffff" : (life > 0.82 ? root.core(tint) : tint)
                // The floor lifts on a light theme: a 10%-alpha dot over white
                // is not a faint dot, it is no dot.
                opacity: (glittering ? 0.35 : 0)
                       + (root.darkSurface ? 0.10 : 0.30)
                       + (root.darkSurface ? 0.90 : 0.70) * life * life
              }
            }

            // ---- route preview
            Repeater {
              model: root.route.length

              Item {
                id: hopItem
                readonly property var hop: root.route[index]
                readonly property int cell: boardArea.cell
                readonly property color tint: hop && hop.fatal
                  ? root.dangerColor
                  : root.carColor(hop ? hop.car : 0)

                visible: !!hop
                x: hop ? (hop.cell % root.cols) * cell : 0
                y: hop ? Math.floor(hop.cell / root.cols) * cell : 0
                width: cell
                height: cell

                // A faint guide thread under the dots. Dots alone, evenly
                // sized, read as scattered specks rather than a path — the
                // thread is what ties them into one line at a glance, and
                // it stays well under the dots' own brightness so it reads
                // as a hint of continuity, not a second competing stroke.
                Shape {
                  anchors.fill: parent
                  preferredRendererType: Shape.CurveRenderer
                  opacity: hopItem.hop
                    ? (hopItem.hop.fatal ? 0.5 : 0.22 * (1 - hopItem.hop.step / Math.max(1, root.spec.look)))
                    : 0
                  ShapePath {
                    strokeWidth: Math.max(1, hopItem.cell * 0.05)
                    strokeColor: hopItem.tint
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    startX: hopItem.hop ? root.edgeMid(hopItem.hop.from).x * hopItem.cell : 0
                    startY: hopItem.hop ? root.edgeMid(hopItem.hop.from).y * hopItem.cell : 0
                    PathQuad {
                      x: hopItem.hop ? root.edgeMid(hopItem.hop.exit).x * hopItem.cell : 0
                      y: hopItem.hop ? root.edgeMid(hopItem.hop.exit).y * hopItem.cell : 0
                      controlX: hopItem.cell * 0.5
                      controlY: hopItem.cell * 0.5
                    }
                  }
                }

                // The dots themselves taper in both size and brightness with
                // distance from the car — a comet tail, not a string of
                // uniform beads — which is what makes "soon" and "eventually"
                // readable at a glance instead of requiring a careful look.
                // Sampled across the *whole* look-ahead via `dist` rather than
                // per-hop, so the taper is one smooth curve across every hop
                // instead of resetting at each tile boundary.
                readonly property int dots: 16
                Repeater {
                  model: hopItem.dots

                  Item {
                    id: routeDot
                    readonly property real t: (index + 0.5) / hopItem.dots
                    readonly property var pt: hopItem.hop
                      ? root.quadPoint(root.edgeMid(hopItem.hop.from), { x: 0.5, y: 0.5 },
                                       root.edgeMid(hopItem.hop.exit), t)
                      : { x: 0, y: 0 }
                    readonly property real dist: hopItem.hop
                      ? Math.min(1, (hopItem.hop.step + t) / Math.max(1, root.spec.look))
                      : 0
                    readonly property real op: hopItem.hop
                      ? (hopItem.hop.fatal ? 0.95 : 0.92 - 0.62 * dist)
                      : 0
                    readonly property real sz: hopItem.hop
                      ? (hopItem.hop.fatal ? 1.0 : 1.0 - 0.55 * dist)
                      : 0

                    x: pt.x * hopItem.cell
                    y: pt.y * hopItem.cell
                    width: 1
                    height: 1
                    visible: !!hopItem.hop

                    Rectangle {
                      anchors.centerIn: parent
                      width: hopItem.cell * 0.12 * routeDot.sz
                      height: width
                      radius: width / 2
                      color: hopItem.tint
                      opacity: 0.35 * root.glow * routeDot.op
                    }
                    Rectangle {
                      anchors.centerIn: parent
                      width: hopItem.cell * 0.052 * routeDot.sz
                      height: width
                      radius: width / 2
                      color: root.core(hopItem.tint)
                      opacity: routeDot.op
                    }
                  }
                }

                // Where the route is about to drive into an obstacle, say so
                // loudly — the last safe tile before it, not the obstacle
                // itself, since that's the one flip that still avoids it.
                Rectangle {
                  id: exitMark
                  anchors.centerIn: parent
                  visible: !!hopItem.hop && hopItem.hop.fatal
                  width: hopItem.cell * 0.34
                  height: width
                  radius: width / 2
                  color: "transparent"
                  border.width: Math.max(2, hopItem.cell * 0.05)
                  border.color: root.dangerColor
                  SequentialAnimation on opacity {
                    running: exitMark.visible
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.25; duration: 420 }
                    NumberAnimation { to: 1.0;  duration: 420 }
                  }
                }
              }
            }

            // ---- obstacles. Fixed hazards rather than another timed
            // pickup, so they read as terrain: a diamond rather than a
            // circle (nothing else on the board is a diamond), dangerColor
            // rather than any playing-piece hue, and a slow pulse rather
            // than the sharper flicker a live threat gets — this is
            // something to route around, not something reacting to you.
            Repeater {
              model: root.obstacles.length

              Item {
                id: obstacleSlot
                readonly property int cell: boardArea.cell
                readonly property int obCell: root.obstacles[index]

                x: (obCell % root.cols) * cell
                y: Math.floor(obCell / root.cols) * cell
                width: cell
                height: cell

                // A ground shadow, offset rather than centered, is the same
                // "this sits above the board" cue the cars' own contact
                // shadow already gives them — without it the obstacle read
                // as printed on the board rather than standing on it.
                Rectangle {
                  x: parent.width * 0.5 - width / 2 + obstacleSlot.cell * 0.03
                  y: parent.height * 0.5 - height / 2 + obstacleSlot.cell * 0.05
                  width: obstacleSlot.cell * 0.46
                  height: width * 0.55
                  radius: width / 2
                  color: root.fade("#000000", root.darkSurface ? 0.35 : 0.18)
                }

                Rectangle {
                  id: obstacleGlow
                  anchors.centerIn: parent
                  width: obstacleSlot.cell * 0.62
                  height: width
                  rotation: 45
                  color: root.fade(root.dangerColor, 0.16 * root.glow)
                  SequentialAnimation on opacity {
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.5; duration: 900; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 1.0; duration: 900; easing.type: Easing.InOutSine }
                  }
                }

                // A slow beacon ping rather than the sharper flicker a live
                // threat gets — this is marked terrain, announcing itself
                // the same way the turn-shockwave ring does elsewhere on
                // this board, just looping instead of one-shot.
                Rectangle {
                  id: hazardBeacon
                  anchors.centerIn: parent
                  width: obstacleSlot.cell * 0.42
                  height: width
                  radius: width / 2
                  color: "transparent"
                  border.width: Math.max(1, obstacleSlot.cell * 0.03)
                  border.color: root.dangerColor
                  opacity: 0.7

                  SequentialAnimation {
                    running: true
                    loops: Animation.Infinite
                    ScriptAction { script: { hazardBeacon.width = obstacleSlot.cell * 0.42; hazardBeacon.opacity = 0.7 } }
                    ParallelAnimation {
                      NumberAnimation { target: hazardBeacon; property: "width"; to: obstacleSlot.cell * 0.80; duration: 1400; easing.type: Easing.OutQuad }
                      NumberAnimation { target: hazardBeacon; property: "opacity"; to: 0; duration: 1400 }
                    }
                    PauseAnimation { duration: 300 }
                  }
                }

                // The hazard badge itself, one layer deeper than before: an
                // outer ring, a darkened mid fill, a bright core — a target
                // rather than a flat tinted diamond.
                Rectangle {
                  anchors.centerIn: parent
                  width: obstacleSlot.cell * 0.44
                  height: width
                  rotation: 45
                  color: "transparent"
                  border.width: Math.max(1, obstacleSlot.cell * 0.05)
                  border.color: root.dangerColor
                }
                Rectangle {
                  anchors.centerIn: parent
                  width: obstacleSlot.cell * 0.34
                  height: width
                  rotation: 45
                  color: root.mix(root.boardBg, root.dangerColor, 0.40)
                  border.width: Math.max(1, obstacleSlot.cell * 0.03)
                  border.color: root.fade(root.dangerColor, 0.6)
                }
                Rectangle {
                  anchors.centerIn: parent
                  width: obstacleSlot.cell * 0.14
                  height: width
                  rotation: 45
                  color: root.core(root.dangerColor)
                }
              }
            }

            // ---- coins
            Repeater {
              model: root.coins.length

              Item {
                id: coinSlot
                readonly property var coin: root.coins[index]
                readonly property int cell: boardArea.cell
                // Reading `frame` is what keeps the fuse ticking down.
                readonly property real fuse: coin
                  ? Math.max(0, 1 - (root.frame, Date.now() - coin.born) / root.coinLife)
                  : 0

                visible: !!coin
                x: coin ? (coin.cell % root.cols) * cell : 0
                y: coin ? Math.floor(coin.cell / root.cols) * cell : 0
                width: cell
                height: cell

                // Scaled down from the full tile: at 1:1 a coin was as big
                // as the car standing on it, which made the board read as
                // "coins with some rails between them" rather than a track
                // with something worth detouring for sitting on it.
                Coin {
                  anchors.centerIn: parent
                  cell: coinSlot.cell * 0.62
                  fuse: coinSlot.fuse
                  phase: index * 0.85
                }
              }
            }

            // ---- collection bursts
            Repeater {
              model: root.pops.length

              Item {
                id: popItem
                readonly property var pop: root.pops[index]
                readonly property int cell: boardArea.cell

                visible: !!pop
                x: pop ? (pop.cell % root.cols) * cell : 0
                y: pop ? Math.floor(pop.cell / root.cols) * cell : 0
                width: cell
                height: cell

                Rectangle {
                  id: popRing
                  anchors.centerIn: parent
                  width: popItem.cell * 0.30
                  height: width
                  radius: width / 2
                  color: "transparent"
                  border.width: Math.max(2, popItem.cell * 0.05)
                  border.color: root.coinColor
                }

                Text {
                  id: popPlus
                  anchors.horizontalCenter: parent.horizontalCenter
                  y: popItem.cell * 0.30
                  text: "+1"
                  color: root.coinColor
                  font.family: root.fontFamily
                  font.pixelSize: Math.max(9, Math.round(popItem.cell * 0.26))
                  font.bold: true
                }

                // A real simulated burst, not another hand-tweened ring: seven
                // motes launched upward into a spread and pulled back down by
                // their own gravity, which is what a coin actually popping
                // loose looks like. ItemParticle reuses the game's own dot
                // language (a plain glowing Rectangle) rather than needing an
                // image asset the way ImageParticle would.
                ParticleSystem {
                  id: popParticles
                  anchors.fill: parent
                }
                ItemParticle {
                  system: popParticles
                  fade: true
                  delegate: Component {
                    Rectangle {
                      width: Math.max(1, popItem.cell * 0.09)
                      height: width
                      radius: width / 2
                      color: root.core(root.coinColor)
                    }
                  }
                }
                Emitter {
                  id: popEmitter
                  system: popParticles
                  x: popItem.cell / 2
                  y: popItem.cell / 2
                  emitRate: 0
                  lifeSpan: 480
                  lifeSpanVariation: 140
                  size: 1
                  endSize: 1
                  velocity: AngleDirection {
                    angle: 270; angleVariation: 130
                    magnitude: popItem.cell * 2.4; magnitudeVariation: popItem.cell * 0.9
                  }
                  acceleration: PointDirection { y: popItem.cell * 5 }
                }

                Component.onCompleted: { popAnim.start(); popEmitter.burst(7) }
                ParallelAnimation {
                  id: popAnim
                  NumberAnimation { target: popRing; property: "width"; to: popItem.cell * 1.05; duration: 420; easing.type: Easing.OutQuad }
                  NumberAnimation { target: popRing; property: "opacity"; to: 0; duration: 460 }
                  NumberAnimation { target: popPlus; property: "y"; to: -popItem.cell * 0.15; duration: 560; easing.type: Easing.OutQuad }
                  NumberAnimation { target: popPlus; property: "opacity"; to: 0; duration: 560 }
                }
              }
            }

            // ---- near misses. `miss.x`/`miss.y` are continuous board-
            // fraction coordinates (the midpoint between the two cars),
            // not a cell index, so this positions directly rather than
            // through the `cell % cols` math every other overlay uses.
            Repeater {
              model: root.misses.length

              Item {
                id: missItem
                readonly property var miss: root.misses[index]
                readonly property int cell: boardArea.cell

                visible: !!miss
                x: miss ? miss.x * cell : 0
                y: miss ? miss.y * cell : 0
                width: 0
                height: 0

                Rectangle {
                  id: missRing
                  anchors.centerIn: parent
                  width: missItem.cell * 0.20
                  height: width
                  radius: width / 2
                  color: "transparent"
                  border.width: Math.max(2, missItem.cell * 0.045)
                  border.color: "#ffffff"
                  opacity: 0.9
                }
                // Four ticks flung outward read as "just missed" rather than
                // as a second, smaller wreck, which is what a filled burst
                // would have said.
                Repeater {
                  model: 4
                  Rectangle {
                    id: missTick
                    readonly property real ang: index * (Math.PI / 2) + Math.PI / 4
                    width: Math.max(1, missItem.cell * 0.09)
                    height: Math.max(1, missItem.cell * 0.028)
                    radius: height / 2
                    color: "#ffffff"
                    x: -width / 2
                    y: -height / 2
                    rotation: missTick.ang * 180 / Math.PI
                    transform: Translate {
                      x: Math.cos(missTick.ang) * missItem.cell * 0.14
                      y: Math.sin(missTick.ang) * missItem.cell * 0.14
                    }
                  }
                }

                Component.onCompleted: missAnim.start()
                ParallelAnimation {
                  id: missAnim
                  NumberAnimation { target: missRing; property: "width"; to: missItem.cell * 0.62; duration: 340; easing.type: Easing.OutQuad }
                  NumberAnimation { target: missRing; property: "opacity"; to: 0; duration: 380 }
                  NumberAnimation { target: missItem; property: "scale"; from: 0.7; to: 1.35; duration: 400; easing.type: Easing.OutQuad }
                  NumberAnimation { target: missItem; property: "opacity"; to: 0; duration: 400 }
                }
              }
            }

            // ---- wreck debris. Loaded on a crash, so the fragments'
            // one-shot animations start exactly when the wreck happens; a
            // wreck that only cost a car keeps it around just long enough to
            // play out via wreckFlash, since phase never becomes "crashed".
            Loader {
              anchors.fill: parent
              active: root.phase === "crashed" || boardArea.wreckFlash
              sourceComponent: Repeater {
                model: 7

                Rectangle {
                  id: frag
                  readonly property real ang: root.crashSeed + (index / 7) * Math.PI * 2
                  readonly property real reach: boardArea.cell * (0.7 + (index % 3) * 0.28)
                  width: Math.max(2, boardArea.cell * 0.11)
                  height: width
                  radius: width / 2
                  color: root.dangerColor
                  x: root.crashPoint.x * boardArea.cell - width / 2
                  y: root.crashPoint.y * boardArea.cell - height / 2

                  Component.onCompleted: flyAnim.start()
                  ParallelAnimation {
                    id: flyAnim
                    NumberAnimation { target: frag; property: "x"; to: frag.x + Math.cos(frag.ang) * frag.reach; duration: 520; easing.type: Easing.OutQuad }
                    NumberAnimation { target: frag; property: "y"; to: frag.y + Math.sin(frag.ang) * frag.reach; duration: 520; easing.type: Easing.OutQuad }
                    NumberAnimation { target: frag; property: "scale"; to: 0.35; duration: 560 }
                    NumberAnimation { target: frag; property: "opacity"; to: 0; duration: 580 }
                  }
                }
              }
            }

            // ---- cars
            Repeater {
              model: root.cars.length

              Item {
                id: carItem
                readonly property var st: (root.frame, root.carState(index, boardArea.cell))

                x: st.x
                y: st.y
                width: 0
                height: 0
                rotation: st.angle

                Racer {
                  anchors.centerIn: parent
                  cell: boardArea.cell
                  variant: root.variantFor(index)
                  tint: root.carColor(index)
                  isPlayer: !!(root.cars[index] && root.cars[index].player)
                  wrecked: root.phase === "crashed"
                }
              }
            }
          }

          // ---- crash flash
          Rectangle {
            id: crashFlash
            anchors.fill: parent
            radius: parent.radius
            color: root.dangerColor
            opacity: 0
            NumberAnimation {
              id: flashAnim
              target: crashFlash
              property: "opacity"
              from: 0.42
              to: 0
              duration: 380
              easing.type: Easing.OutQuad
            }
          }

          // ---- overlays
          //
          // The scrim used to appear the instant the phase flipped, which drew it
          // straight over the flash and the debris and wasted both. On a wreck it
          // now waits for them to play out before it fades in.
          Rectangle {
            id: overlay
            anchors.fill: parent
            radius: parent.radius
            visible: root.phase !== "running" || root.helpOpen || root.menuOpen
            opacity: 0
            color: {
              var c = root.toColor(root.background)
              return Qt.rgba(c.r, c.g, c.b, 0.86)
            }

            onVisibleChanged: {
              if (visible) overlayIn.restart()
              else overlay.opacity = 0
            }
            SequentialAnimation {
              id: overlayIn
              PauseAnimation { duration: root.phase === "crashed" ? 460 : 0 }
              NumberAnimation { target: overlay; property: "opacity"; to: 1.0; duration: 260 }
            }

            // A card rather than free-floating text. The scrim on its own left the
            // words lying on the board with nothing under them, and the three states
            // this thing has — paused, wrecked, explaining itself — were told apart
            // only by the color of one line of type.
            Rectangle {
              id: card

              readonly property color accentHue: root.menuOpen ? root.carHues[root.chosenCar]
                : root.highScoreEntry ? root.coinColor
                : root.helpOpen ? root.coinColor
                : root.phase === "crashed" ? root.dangerColor
                : root.levelColor

              anchors.centerIn: parent
              width: Math.min(parent.width - Style.spacing.lg * 2, Style.space(370))
              // Capped to what the board frame actually has, not just to the
              // content's own natural height — on a small board (Cruise's 5
              // rows especially) the help card's full text plus its two-
              // column key grid can need more room than the frame has, and
              // nothing here clips, so an uncapped card spilled straight
              // over the readout row parked underneath. Scrolls instead
              // (see the Flickable below) whenever it doesn't fit.
              height: Math.min(cardBody.height + Style.spacing.xxl * 2,
                                parent.height - Style.spacing.lg * 2)
              radius: Math.max(root.cornerRadius, Style.space(4))
              color: root.mix(root.background, root.darkSurface ? "#000000" : "#ffffff", 0.30)
              border.width: Math.max(1, Style.space(1))
              border.color: root.fade(card.accentHue, 0.70)
              clip: true

              Rectangle {
                anchors.fill: parent
                anchors.margins: -Math.max(2, Style.space(3))
                radius: parent.radius + Style.space(3)
                color: "transparent"
                border.width: Math.max(1, Style.space(2))
                border.color: root.fade(card.accentHue, 0.18)
                z: -1
              }

              // Plain `anchors.centerIn` sized `cardBody` to fit before; now
              // that `card` itself can be shorter than `cardBody`'s natural
              // height, this scrolls instead of centering the overflow off
              // both edges. `interactive` only turns on when it's actually
              // needed, so this behaves exactly as before whenever the
              // content already fits.
              Flickable {
                id: cardScroll
                anchors.fill: parent
                anchors.margins: Style.spacing.xxl
                contentWidth: width
                contentHeight: cardBody.height
                interactive: contentHeight > height
                boundsBehavior: Flickable.StopAtBounds
                clip: true

              Column {
                id: cardBody
                width: parent.width
                spacing: Style.spacing.md

                // Everything below is the paused/wrecked/help/high-score card
                // this always was; the start menu (see the sibling Column
                // right after it closes) is its own separate screen, never
                // shown at the same time, so nothing here needed its own
                // menuOpen guard beyond this one wrapper.
                Column {
                width: parent.width
                spacing: Style.spacing.md
                visible: !root.menuOpen

                // The state says itself in the thing the state is about: a wreck shows
                // a wrecked car, and the help card shows the coin the whole game is a
                // long argument about.
                Item {
                  anchors.horizontalCenter: parent.horizontalCenter
                  visible: !root.helpOpen && root.phase === "crashed" && !root.highScoreEntry
                  width: Style.space(34)
                  height: width

                  Racer {
                    anchors.centerIn: parent
                    cell: parent.width
                    variant: root.chosenCar
                    isPlayer: true
                    wrecked: true
                    idle: true
                    rotation: 26
                  }
                }
                Coin {
                  anchors.horizontalCenter: parent.horizontalCenter
                  visible: root.helpOpen || !!root.highScoreEntry
                  cell: Style.space(30)
                  hud: true
                }

                Text {
                  width: parent.width
                  horizontalAlignment: Text.AlignHCenter
                  text: root.helpOpen ? "how it works"
                      : root.highScoreEntry ? "new high score!"
                      : root.phase !== "crashed" ? "paused"
                      : "wrecked"
                  color: root.highScoreEntry ? root.coinColor
                       : root.helpOpen || root.phase !== "crashed" ? root.foreground
                       : root.dangerColor
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.heading
                  font.bold: true
                }
                Text {
                  width: parent.width
                  // Help is a reference, not a poster: centered wrapping made
                  // every line a different width and buried the wreck rule in
                  // the middle of a paragraph.
                  horizontalAlignment: root.helpOpen ? Text.AlignLeft : Text.AlignHCenter
                  wrapMode: Text.WordWrap
                  text: root.helpOpen
                    ? "The cars never stop, and the board wraps \u2014 drive off one edge and you come back on the other, still mid-lap. Move the cursor and turn the tile under it: crossing, one diagonal, the other. Clicking does the same.\n\nThe colored trail is where a car is about to go. Bend it onto the coins before their dial runs out. A flashing red ring means that trail hits an obstacle. Gold tiles are welded shut; they flinch instead of wrecking you.\n\nThree ways to wreck a car: turn the tile it is standing on, drive it into an obstacle, or put two cars in the same place. A spare car costs only that life. The run ends when the last one goes. Cruise never fields a second car or an obstacle."
                    : root.highScoreEntry
                      ? root.score + " coins on " + root.spec.name + " \u2014 enter your name"
                    : root.phase === "crashed"
                      ? root.crashReason + "  \u00b7  " + root.score + " coins on " + root.spec.name
                      : "back to it"
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }

                // A plain text field rather than arcade letter-cycling —
                // labrat asked for normal typing, so this reads `event.text`
                // in handleKey() directly rather than reimplementing a
                // key-to-character map. The blink is a fixed 500ms toggle
                // rather than something bound to a shared clock, since only
                // one of these can ever be on screen at once.
                Rectangle {
                  id: nameField
                  anchors.horizontalCenter: parent.horizontalCenter
                  visible: !!root.highScoreEntry
                  width: Style.space(160)
                  height: Style.space(40)
                  radius: Style.space(4)
                  color: root.fade(root.coinColor, 0.12)
                  border.width: Math.max(1, Style.space(2))
                  border.color: root.coinColor

                  property bool blink: true
                  Timer {
                    interval: 500
                    running: nameField.visible
                    repeat: true
                    onTriggered: nameField.blink = !nameField.blink
                  }

                  Text {
                    anchors.centerIn: parent
                    text: (root.highScoreEntry ? root.highScoreEntry.text : "")
                          + (nameField.blink ? "_" : " ")
                    textFormat: Text.PlainText
                    color: root.coinColor
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.heading
                    font.bold: true
                  }
                }

                // The board for whichever level you just played, so the
                // number you were chasing stays on screen after you miss it \u2014
                // and so a run that didn't qualify still shows what would
                // have. Only while not mid-entry: the letter slots above are
                // already the answer to "did I make it."
                Column {
                  anchors.horizontalCenter: parent.horizontalCenter
                  visible: !root.helpOpen && root.phase === "crashed" && !root.highScoreEntry
                           && (root.highScores[root.spec.key] || []).length > 0
                  spacing: Style.spacing.xxs

                  Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "top scores \u00b7 " + root.spec.name
                    color: root.fade(root.foreground, 0.55)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                  }
                  Repeater {
                    model: root.highScores[root.spec.key] || []
                    Row {
                      required property var modelData
                      required property int index
                      spacing: Style.spacing.sm

                      Item {
                        width: Style.space(44)
                        height: Style.space(44)
                        anchors.verticalCenter: parent.verticalCenter

                        Medal {
                          visible: index < 3
                          rank: index + 1
                          width: Style.space(44)
                          height: width
                          anchors.centerIn: parent
                        }
                        Text {
                          visible: index >= 3
                          anchors.centerIn: parent
                          text: (index + 1) + "."
                          color: root.fade(root.foreground, 0.45)
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.caption
                          font.bold: true
                        }
                      }
                      Text {
                        width: Style.space(46)
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.name
                        textFormat: Text.PlainText
                        color: root.dim
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        font.bold: true
                      }
                      Text {
                        width: Style.space(36)
                        anchors.verticalCenter: parent.verticalCenter
                        horizontalAlignment: Text.AlignRight
                        text: modelData.score
                        color: root.coinColor
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                      }
                    }
                  }
                }

                Item { width: 1; height: Style.spacing.xs }

                // Help gets the whole key reference, two columns wide. The other two
                // states get only the key that gets you out of them.
                Grid {
                  anchors.horizontalCenter: parent.horizontalCenter
                  visible: root.helpOpen
                  columns: 2
                  columnSpacing: Style.spacing.xl
                  rowSpacing: Style.spacing.sm
                  horizontalItemAlignment: Grid.AlignLeft

                  Hint { keys: ["\u2190", "\u2191", "\u2193", "\u2192"]; label: "move" }
                  Hint { keys: ["space"]; label: "turn the tile" }
                  Hint { keys: ["1", "2", "3", "4"]; label: "level" }
                  Hint { keys: ["p"]; label: "pause" }
                  Hint { keys: ["r"]; label: "new board" }
                  Hint { keys: ["?"]; label: "help" }
                  Hint { keys: ["q", "esc"]; label: "close" }
                }
                Row {
                  anchors.horizontalCenter: parent.horizontalCenter
                  visible: !!root.highScoreEntry
                  spacing: Style.spacing.lg

                  Hint { keys: ["enter"]; label: "confirm" }
                  Hint { keys: ["\u232b"]; label: "delete" }
                  Hint { keys: ["esc"]; label: "cancel" }
                }
                Row {
                  anchors.horizontalCenter: parent.horizontalCenter
                  visible: !root.helpOpen && root.phase === "crashed" && !root.highScoreEntry
                  spacing: Style.spacing.lg

                  Hint { keys: ["space", "r"]; label: "new board" }
                  Hint { keys: ["1", "2", "3", "4"]; label: "level" }
                }
                Row {
                  anchors.horizontalCenter: parent.horizontalCenter
                  visible: !root.helpOpen && root.phase === "paused"
                  spacing: Style.spacing.lg

                  Hint { keys: ["space", "p"]; label: "go" }
                }
                }

                // ---- start menu: shown at cold boot, and reopenable via the
                // "garage" button in the live readout (only while actually
                // playing, so it can never end up layered under the wrecked
                // or help card — see the guards on that button, and on
                // handleKey's own menuOpen block which owns the keyboard
                // outright while this is up, the same way name entry does).
                Column {
                  width: parent.width
                  spacing: Style.spacing.lg
                  visible: root.menuOpen

                  Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: "omacircuit"
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.heading
                    font.bold: true
                  }

                  Column {
                    width: parent.width
                    spacing: Style.spacing.sm

                    Text {
                      width: parent.width
                      horizontalAlignment: Text.AlignHCenter
                      text: "choose your car"
                      color: root.fade(root.foreground, 0.55)
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      font.bold: true
                    }

                    Row {
                      anchors.horizontalCenter: parent.horizontalCenter
                      spacing: Style.spacing.lg

                      Repeater {
                        model: 3

                        Rectangle {
                          id: pickSlot
                          required property int index
                          readonly property bool picked: root.chosenCar === index
                          width: Style.space(56)
                          height: Style.space(56)
                          radius: Style.space(8)
                          color: picked ? root.fade(root.carHues[index], 0.18)
                               : pickHover.hovered ? root.fade(root.gridNeon, 0.10) : "transparent"
                          border.width: Math.max(1, Style.space(2))
                          border.color: picked ? root.carHues[index]
                               : pickHover.hovered ? root.fade(root.gridNeon, 0.6) : root.fade(root.gridNeon, 0.35)

                          Racer {
                            anchors.centerIn: parent
                            cell: Style.space(34)
                            variant: pickSlot.index
                            tint: root.carHues[pickSlot.index]
                            idle: true
                          }

                          HoverHandler { id: pickHover }
                          TapHandler { onTapped: root.setChosenCar(pickSlot.index) }
                        }
                      }
                    }
                  }

                  // The level's own top five, medals and all — the same
                  // reason it's already pinned to the wrecked card: the
                  // number to chase is worth seeing before the run that
                  // chases it, not just after.
                  Column {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: (root.highScores[root.spec.key] || []).length > 0
                    spacing: Style.spacing.xxs

                    Text {
                      anchors.horizontalCenter: parent.horizontalCenter
                      text: "top scores · " + root.spec.name
                      color: root.fade(root.foreground, 0.55)
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      font.bold: true
                    }
                    Repeater {
                      model: (root.highScores[root.spec.key] || []).slice(0, 3)
                      Row {
                        required property var modelData
                        required property int index
                        spacing: Style.spacing.sm

                        Medal { rank: index + 1; width: Style.space(26); height: width; anchors.verticalCenter: parent.verticalCenter }
                        Text {
                          width: Style.space(46)
                          anchors.verticalCenter: parent.verticalCenter
                          text: modelData.name
                          color: root.dim
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.caption
                          font.bold: true
                        }
                        Text {
                          width: Style.space(36)
                          anchors.verticalCenter: parent.verticalCenter
                          horizontalAlignment: Text.AlignRight
                          text: modelData.score
                          color: root.coinColor
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.caption
                        }
                      }
                    }
                  }

                  Rectangle {
                    id: startBtn
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: startText.implicitWidth + Style.spacing.lg * 2
                    height: startText.implicitHeight + Style.spacing.sm * 2
                    radius: height / 2
                    color: root.fade(root.carHues[root.chosenCar], startHover.hovered ? 0.28 : 0.18)
                    border.width: Math.max(1, Style.space(2))
                    border.color: root.carHues[root.chosenCar]

                    Text {
                      id: startText
                      anchors.centerIn: parent
                      text: "start · space"
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      font.bold: true
                    }

                    HoverHandler { id: startHover }
                    TapHandler { onTapped: root.menuOpen = false }
                  }
                }
              }
              }
            }

            TapHandler {
              onTapped: {
                if (root.menuOpen) { /* only the start button and Space begin */ }
                else if (root.helpOpen) root.helpOpen = false
                else if (root.highScoreEntry) { /* tapping through initials does nothing */ }
                else if (root.phase === "crashed") root.newGame()
                else root.phase = "running"
              }
            }
          }
        }
          // The live numbers sit under the board rather than up in the header:
          // that is where your eyes already are, and it puts the reclaimed
          // vertical space to work.
          Row {
            id: readout
            // The overlay scrim now reaches down over this row too (see the
            // note on `overlay` above) so the card always has room — no
            // reason to leave this showing half-dimmed underneath it.
            visible: root.phase === "running" && !root.helpOpen && !root.menuOpen
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Style.spacing.xl

            // The score carries an actual coin rather than the word "coins": it is
            // the same component the board draws, stopped mid-turn, so the thing you
            // are collecting and the thing you are counting are visibly one object.
            Row {
              spacing: Style.spacing.xs

              Coin {
                anchors.verticalCenter: parent.verticalCenter
                cell: Math.round(Style.font.subtitle * 2.0)
                hud: true
              }
              Text {
                id: scoreText
                anchors.verticalCenter: parent.verticalCenter
                text: root.score
                color: root.coinColor
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true

                onTextChanged: scorePop.restart()
                SequentialAnimation {
                  id: scorePop
                  NumberAnimation { target: scoreText; property: "scale"; to: 1.35; duration: 90; easing.type: Easing.OutQuad }
                  NumberAnimation { target: scoreText; property: "scale"; to: 1.0;  duration: 200; easing.type: Easing.OutBack }
                }
              }
            }

            Rectangle {
              anchors.verticalCenter: parent.verticalCenter
              width: 1
              height: Math.round(Style.font.subtitle * 1.3)
              color: root.fade(root.gridNeon, 0.40)
            }

            Row {
              spacing: Style.spacing.xs

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "best"
                color: root.fade(root.foreground, 0.45)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.best
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.subtitle
                font.bold: true
              }
            }

            Rectangle {
              anchors.verticalCenter: parent.verticalCenter
              width: 1
              height: Math.round(Style.font.subtitle * 1.3)
              color: root.fade(root.gridNeon, 0.40)
            }

            // This used to read "cars 3", which is a number you then have to map onto
            // three colored shapes on the board. Drawing the shapes themselves skips
            // the mapping, and it is the only place the three silhouettes can be
            // compared side by side.
            Row {
              spacing: Style.spacing.xxs

              Repeater {
                model: root.cars.length

                Racer {
                  anchors.verticalCenter: parent.verticalCenter
                  cell: Math.round(Style.font.subtitle * 2.0)
                  variant: root.variantFor(index)
                  tint: root.carColor(index)
                  isPlayer: !!(root.cars[index] && root.cars[index].player)
                  idle: true
                }
              }
            }

            Rectangle {
              anchors.verticalCenter: parent.verticalCenter
              width: 1
              height: Math.round(Style.font.subtitle * 1.3)
              color: root.fade(root.gridNeon, 0.40)
            }

            // `r` already did this at any time, but it only ever showed up
            // as a key hint buried in the help/wrecked overlays — never
            // something to click while actually playing.
            Rectangle {
              id: newBoardBtn
              visible: !root.menuOpen
              anchors.verticalCenter: parent.verticalCenter
              width: newBoardText.implicitWidth + Style.spacing.md * 2
              height: newBoardText.implicitHeight + Style.spacing.xs * 2
              radius: height / 2
              color: newBoardHover.hovered ? root.fade(root.gridNeon, 0.16) : "transparent"
              border.width: 1
              border.color: root.fade(root.gridNeon, 0.45)

              Text {
                id: newBoardText
                anchors.centerIn: parent
                text: "new board"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              HoverHandler { id: newBoardHover }
              TapHandler { onTapped: root.newGame() }
            }

            // Reachable only while actually playing: the menu's own card
            // shares the same overlay Rectangle as help/paused/wrecked, so
            // opening it from inside any of those would layer two cards on
            // top of each other rather than showing either cleanly.
            Rectangle {
              id: garageBtn
              visible: root.phase === "running" && !root.helpOpen && !root.menuOpen
              anchors.verticalCenter: parent.verticalCenter
              width: garageText.implicitWidth + Style.spacing.md * 2
              height: garageText.implicitHeight + Style.spacing.xs * 2
              radius: height / 2
              color: garageHover.hovered ? root.fade(root.carHues[root.chosenCar], 0.16) : "transparent"
              border.width: 1
              border.color: root.fade(root.carHues[root.chosenCar], 0.45)

              Text {
                id: garageText
                anchors.centerIn: parent
                text: "garage"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              HoverHandler { id: garageHover }
              TapHandler { onTapped: root.menuOpen = true }
            }
          }
        }
      }


      // ------------------------------------------------------------ status
      // Keys drawn as keys. A run-on sentence of words and interpuncts is
      // legible, but it reads as prose when what it is is a control reference.
      // Only the four you need in the first ten seconds are here; the rest live
      // in the help overlay, which is what "?" is for.
      Flow {
        id: statusLine
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Style.spacing.lg

        Hint { keys: ["\u2190", "\u2191", "\u2193", "\u2192"]; label: "move" }
        Hint { keys: ["space"]; label: "turn the tile" }
        Hint { keys: ["1", "2", "3", "4"]; label: "level" }
        Hint { keys: ["?"]; label: "help" }
      }
    }
  }

  // ================================================================== pieces
  //
  // The board and the readout draw the same coin and the same cars, so both
  // live here as inline components rather than as two drifting copies. Every
  // dimension is a fraction of `cell`, which is the only thing either of them
  // needs to be told about size.

  // A coin is a disc caught turning: the face narrows to a sliver and opens
  // back out. That is what makes it read as struck metal rather than as a dot,
  // and it costs one cosine. The countdown dial around it deliberately does
  // *not* turn, because it is a readout and the eye needs it to hold still.
  component Coin: Item {
    id: coin

    property real cell: 20
    property real fuse: 1.0
    // The readout coin is the same object with its clock stopped, parked at an
    // angle that shows it is a disc and not a circle.
    property bool hud: false
    property real spin: hud ? 0.72 : 0
    property real bob: 0
    // The Repeater rebuilds every delegate whenever a coin is taken or
    // spawned, which restarts all of their animations on the same frame:
    // three coins flipping in lockstep read as one object with three faces.
    // The phase is per coin and constant, so they beat against each other.
    property real phase: 0

    readonly property bool urgent: !hud && fuse < 0.25
    readonly property color tint: urgent ? root.dangerColor : root.coinColor
    // Never allowed to close all the way. A coin that vanishes for a frame
    // reads as a dropped frame, not as an edge.
    readonly property real face: Math.max(0.17, Math.abs(Math.cos(spin + phase)))
    readonly property real r: cell * 0.26

    implicitWidth: cell
    implicitHeight: cell

    NumberAnimation on spin {
      running: !coin.hud
      loops: Animation.Infinite
      from: 0
      to: Math.PI * 2
      // The spin is the second warning. It doubles up as the fuse runs out,
      // which catches the eye even where the dial is at the edge of vision.
      duration: coin.urgent ? 720 : 1600
    }

    SequentialAnimation on bob {
      running: !coin.hud
      loops: Animation.Infinite
      NumberAnimation { to: -1; duration: 880; easing.type: Easing.InOutSine }
      NumberAnimation { to: 0;  duration: 880; easing.type: Easing.InOutSine }
    }

    // Everything that hovers, kept together so the dial can stay put.
    Item {
      anchors.fill: parent
      transform: Translate { y: coin.bob * coin.cell * 0.055 }

      Rectangle {
        anchors.centerIn: parent
        width: coin.cell * 0.82
        height: width
        radius: width / 2
        color: coin.tint
        opacity: (0.07 + 0.13 * coin.fuse) * (0.75 + 0.25 * coin.face) * (0.25 + 0.75 * root.glow)
      }

      Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        // The face. Its x radius is the whole animation.
        ShapePath {
          // Lit from the upper left and falling away to the lower right. A
          // flat fill was legible but plastic; two stops and a shadow are the
          // difference between a disc and a struck coin.
          fillGradient: LinearGradient {
            x1: coin.cell * 0.5 - coin.r
            y1: coin.cell * 0.5 - coin.r
            x2: coin.cell * 0.5 + coin.r
            y2: coin.cell * 0.5 + coin.r

            GradientStop { position: 0.0;  color: root.mix(coin.tint, "#ffffff", 0.55) }
            GradientStop { position: 0.42; color: coin.tint }
            GradientStop { position: 1.0;  color: root.mix(coin.tint, "#000000", 0.42) }
          }
          strokeColor: root.core(coin.tint)
          strokeWidth: Math.max(1, coin.cell * 0.035)
          PathAngleArc {
            centerX: coin.cell / 2
            centerY: coin.cell / 2
            radiusX: coin.r * coin.face
            radiusY: coin.r
            startAngle: 0
            sweepAngle: 360
          }
        }
        // An inner ring and a diamond, struck into the face. Both narrow with
        // it, which is what keeps the disc from looking like a printed sticker.
        ShapePath {
          fillColor: "transparent"
          strokeColor: root.fade(root.mix(coin.tint, "#000000", 0.5), 0.75)
          strokeWidth: Math.max(1, coin.cell * 0.028)
          PathAngleArc {
            centerX: coin.cell / 2
            centerY: coin.cell / 2
            radiusX: coin.r * 0.64 * coin.face
            radiusY: coin.r * 0.64
            startAngle: 0
            sweepAngle: 360
          }
        }
        // A specular sweep on the upper left, brightest when the face is
        // widest. Angles run clockwise from 3 o'clock with y downwards, so
        // 205 through 255 is the upper-left shoulder of the disc.
        ShapePath {
          fillColor: "transparent"
          strokeColor: root.fade("#ffffff", 0.50 * coin.face * coin.face)
          strokeWidth: Math.max(1, coin.cell * 0.045)
          capStyle: ShapePath.RoundCap
          PathAngleArc {
            centerX: coin.cell / 2
            centerY: coin.cell / 2
            radiusX: coin.r * 0.74 * coin.face
            radiusY: coin.r * 0.74
            startAngle: 205
            sweepAngle: 50
          }
        }
      }

      // The official Omarchy mark, struck into the face rather than printed on
      // it: colorized to a darkened cut of the coin's own metal, and squashed
      // by the same `face` factor as the disc so it turns with the coin.
      Image {
        id: coinMark
        anchors.centerIn: parent
        width: Math.max(1, coin.r * 1.10 * coin.face)
        height: Math.max(1, coin.r * 1.10)
        source: root.omarchyIcon
        fillMode: Image.Stretch
        sourceSize.width: 96
        sourceSize.height: 96
        smooth: true
        visible: false
      }
      MultiEffect {
        anchors.fill: coinMark
        source: coinMark
        colorization: 1.0
        colorizationColor: root.mix(coin.tint, "#000000", 0.66)
        // Fades as the disc turns edge-on, the way a stamped face would.
        opacity: 0.30 + 0.70 * coin.face
      }
    }

    // The fuse, as a dial that drains from the top. The ring the old coin used
    // shrank as it aged, which meant the thing you had to read got smaller
    // exactly as it got urgent.
    Shape {
      anchors.fill: parent
      visible: !coin.hud
      preferredRendererType: Shape.CurveRenderer

      ShapePath {
        fillColor: "transparent"
        strokeColor: root.fade(coin.tint, 0.16)
        strokeWidth: Math.max(1, coin.cell * 0.05)
        PathAngleArc {
          centerX: coin.cell / 2
          centerY: coin.cell / 2
          radiusX: coin.cell * 0.40
          radiusY: coin.cell * 0.40
          startAngle: 0
          sweepAngle: 360
        }
      }
      ShapePath {
        fillColor: "transparent"
        strokeColor: coin.tint
        strokeWidth: Math.max(1, coin.cell * 0.05)
        capStyle: ShapePath.RoundCap
        PathAngleArc {
          centerX: coin.cell / 2
          centerY: coin.cell / 2
          radiusX: coin.cell * 0.40
          radiusY: coin.cell * 0.40
          startAngle: 270
          sweepAngle: Math.max(0.001, 360 * coin.fuse)
        }
      }
    }
  }

  // A car, drawn from `carBodies` with the same halo/hue/core stack as the
  // rails. The cockpit and the exhaust are what turn a colored lozenge into
  // something with a front and a back.
  component Racer: Item {
    id: racer

    property real cell: 20
    property int variant: 0
    property color tint: root.carHues[0]
    property bool wrecked: false
    // The gloss finish is about *whose* car this is, not which silhouette
    // it happens to be wearing — chosenCar can be any of the three variants,
    // so this can't stay hardcoded to variant 0 anymore.
    property bool isPlayer: false
    // The readout glyph holds still: a row of flickering exhausts in the
    // header would pull the eye off the board, which is where it belongs.
    property bool idle: false
    property real flare: 1.0

    readonly property color skin: wrecked ? root.dangerColor : tint
    readonly property var body: root.carBodies[variant % root.carBodies.length]
    readonly property var wheels: root.carWheels[variant % root.carWheels.length]
    readonly property var wings: root.carWings[variant % root.carWings.length]
    // Rubber, not paint. Dark enough to read as a tire against the body, with
    // a lit rim so it still belongs on a neon board.
    readonly property color rubber: root.mix(root.background, "#000000", 0.55)

    implicitWidth: cell
    implicitHeight: cell

    function outline() {
      var out = []
      for (var i = 0; i < body.length; i++)
        out.push(Qt.point(cell * (0.5 + body[i][0]), cell * (0.5 + body[i][1])))
      out.push(out[0])
      return out
    }

    // Deliberately not eased. A flame is a flicker, and interpolating it
    // smoothly turns it into a throb.
    NumberAnimation on flare {
      running: !racer.idle && !racer.wrecked
      loops: Animation.Infinite
      from: 0.70
      to: 1.18
      duration: 130
    }

    // A ground-contact shadow, under everything else. Two stacked ellipses
    // rather than a blurred one: MultiEffect blur is a full extra pass per
    // car, and the board is small enough that a hard-edged soft-opacity
    // stack reads the same at this size for a fraction of the cost. Without
    // this the car looked pasted onto the board rather than sitting on it.
    Rectangle {
      x: racer.cell * 0.5 - width / 2 + racer.cell * 0.02
      y: racer.cell * 0.5 - height / 2 + racer.cell * 0.05
      width: racer.cell * 0.62
      height: racer.cell * 0.30
      radius: height / 2
      color: "#000000"
      opacity: 0.16
    }
    Rectangle {
      x: racer.cell * 0.5 - width / 2 + racer.cell * 0.02
      y: racer.cell * 0.5 - height / 2 + racer.cell * 0.05
      width: racer.cell * 0.44
      height: racer.cell * 0.20
      radius: height / 2
      color: "#000000"
      opacity: 0.20
    }

    // Wings first, then rubber, then the body on top of both.
    Repeater {
      model: racer.wings
      Rectangle {
        required property var modelData
        x: racer.cell * (0.5 + modelData[0]) - width / 2
        y: racer.cell * (0.5 + modelData[1]) - height / 2
        width: Math.max(1, racer.cell * modelData[2])
        height: Math.max(1, racer.cell * modelData[3])
        radius: Math.max(1, racer.cell * 0.010)
        color: root.fade(racer.skin, 0.80)
        border.width: racer.cell > 26 ? 1 : 0
        border.color: root.fade(root.core(racer.skin), 0.7)
      }
    }
    Repeater {
      model: racer.wheels
      Rectangle {
        required property var modelData
        x: racer.cell * (0.5 + modelData[0]) - width / 2
        y: racer.cell * (0.5 + modelData[1]) - height / 2
        width: Math.max(2, racer.cell * modelData[2])
        height: Math.max(1, racer.cell * modelData[3])
        radius: Math.max(1, racer.cell * 0.020)
        color: racer.rubber
        border.width: Math.max(1, racer.cell * 0.014)
        border.color: root.fade(racer.skin, 0.60)

        // A chrome hub rather than one tinted to the body color. Die-cast
        // wheels are the one part that never matches the paint job — they're
        // stamped metal on every casting regardless of colorway — and a
        // hub that took the car's hue instead read as a fourth body panel.
        Rectangle {
          anchors.centerIn: parent
          width: parent.width * 0.34
          height: parent.height * 0.46
          radius: Math.min(width, height) / 2
          color: "#d7dbe2"
          visible: racer.cell > 22

          Rectangle {
            anchors.centerIn: parent
            width: parent.width * 0.5
            height: parent.height * 0.5
            radius: Math.min(width, height) / 2
            color: "#7a828f"
          }
        }
      }
    }

    Shape {
      anchors.fill: parent
      preferredRendererType: Shape.CurveRenderer

      // Exhaust, drawn under the body so the tail eats its blunt end.
      ShapePath {
        fillColor: root.fade(racer.skin, racer.idle || racer.wrecked ? 0 : 0.5)
        strokeColor: "transparent"
        strokeWidth: 0
        startX: racer.cell * 0.30
        startY: racer.cell * (0.5 - 0.06)
        PathLine { x: racer.cell * (0.30 - 0.18 * racer.flare); y: racer.cell * 0.5 }
        PathLine { x: racer.cell * 0.30; y: racer.cell * (0.5 + 0.06) }
      }
      ShapePath {
        fillColor: racer.idle || racer.wrecked ? "transparent" : root.core(racer.skin)
        strokeColor: "transparent"
        strokeWidth: 0
        startX: racer.cell * 0.30
        startY: racer.cell * (0.5 - 0.028)
        PathLine { x: racer.cell * (0.30 - 0.10 * racer.flare); y: racer.cell * 0.5 }
        PathLine { x: racer.cell * 0.30; y: racer.cell * (0.5 + 0.028) }
      }

      // Halo, body, core edge.
      ShapePath {
        fillColor: root.darkSurface ? root.fade(racer.skin, 0.14) : "transparent"
        strokeColor: root.darkSurface ? root.fade(racer.skin, 0.16)
                                      : root.fade(root.boardBg, 0.90)
        strokeWidth: Math.max(2, racer.cell * 0.15)
        joinStyle: ShapePath.RoundJoin
        capStyle: ShapePath.RoundCap
        PathPolyline { path: racer.outline() }
      }
      // A knockout in the board's own color, between the halo and the body.
      // The car drives along a route beam of exactly its own hue, and without
      // this its nose dissolves into the beam it is following.
      ShapePath {
        fillColor: "transparent"
        strokeColor: root.fade(root.boardBg, 0.92)
        strokeWidth: Math.max(2, racer.cell * 0.075)
        joinStyle: ShapePath.RoundJoin
        capStyle: ShapePath.RoundCap
        PathPolyline { path: racer.outline() }
      }
      ShapePath {
        fillColor: root.fade(racer.skin, 0.92)
        // The player's own car gets a real light-to-dark sheen instead of
        // the flat tint every traffic car on the board uses — "why single
        // colored cars, make it stand out" was a fair complaint, and the
        // honest answer is that the traffic cars stay flat on purpose
        // (they're background, not you) while the one you're actually
        // flying gets the paint job. `fillGradient: null` on every other
        // car falls back to the flat `fillColor` above it.
        fillGradient: racer.isPlayer ? bodyGloss : null
        strokeColor: root.core(racer.skin)
        strokeWidth: Math.max(1, racer.cell * 0.035)
        joinStyle: ShapePath.RoundJoin
        PathPolyline { path: racer.outline() }

        // A plain child here would default onto ShapePath's own
        // pathElements list instead of becoming a gradient (and warn:
        // "Cannot assign QQuickShapeLinearGradient to list property
        // pathElements") — declaring it as a property is what makes it a
        // value the fillGradient binding above can actually point to.
        property Gradient bodyGloss: LinearGradient {
          x1: 0; y1: 0
          x2: racer.cell; y2: racer.cell
          GradientStop { position: 0.0; color: root.mix(racer.skin, "#ffffff", 0.5) }
          GradientStop { position: 0.5; color: racer.skin }
          GradientStop { position: 1.0; color: root.mix(racer.skin, "#000000", 0.42) }
        }
      }
      // A die-cast casting has a crisp dark panel line at the body edge
      // regardless of paint color — without it the neon core-stroke above
      // is the only edge the eye gets, and that edge is the same hue as the
      // fill, which reads as glow rather than as a molded body line.
      ShapePath {
        fillColor: "transparent"
        strokeColor: root.fade(root.mix(racer.skin, "#000000", 0.72), 0.85)
        strokeWidth: Math.max(1, racer.cell * 0.018)
        joinStyle: ShapePath.RoundJoin
        PathPolyline { path: racer.outline() }
      }
    }

    // A center racing stripe, painted over the body rather than into its
    // outline. The body is narrow — its own outline is at most ~0.2 cell
    // wide at the cockpit — so the stripe has to be thinner than that to
    // read as a stripe rather than as the body's whole paint job. A pinstripe
    // border is what separates "stripe" from "smear" at this size: real
    // racing stripes are almost always edged, not just a flat fill.
    Rectangle {
      anchors.centerIn: parent
      width: racer.cell * 0.56
      height: Math.max(2, racer.cell * 0.026)
      radius: height / 2
      color: root.darkSurface ? "#f5f5f5" : "#1a1a1a"
      border.width: Math.max(1, racer.cell * 0.008)
      border.color: root.fade(root.mix(racer.skin, "#000000", 0.7), 0.9)
      opacity: racer.wrecked ? 0 : 0.85
    }

    // The clearcoat gloss: one small diagonal streak of light near the
    // cockpit, which is what stops a flat-filled shape from reading as flat.
    // Real paint has a highlight that does not depend on the hue underneath
    // it, so this is the same white streak on every car regardless of
    // color. `body` coordinates run from about -0.29 to +0.38 with the nose
    // at +x, so the cockpit sits noticeably forward of center.
    Rectangle {
      x: racer.cell * 0.58
      y: racer.cell * 0.40
      width: racer.cell * 0.16
      height: racer.cell * 0.045
      radius: height / 2
      rotation: -25
      color: "#ffffff"
      opacity: racer.wrecked ? 0 : 0.28
    }

    // A tinted canopy rather than a flat bright dot. Real glass is dark until
    // something catches it, so the shape that says "cockpit" is a dark lens
    // with one small bright glint on it, not a headlamp-colored blob
    // sitting on top of the paint.
    Rectangle {
      x: racer.cell * 0.54 - width / 2
      y: racer.cell * 0.5 - height / 2
      width: racer.cell * 0.15
      height: racer.cell * 0.105
      radius: height / 2
      color: racer.wrecked ? root.fade(root.dangerColor, 0.8)
                           : root.mix(root.background, "#0a1420", 0.75)
      border.width: Math.max(1, racer.cell * 0.012)
      border.color: root.fade(root.mix(racer.skin, "#000000", 0.5), 0.8)
      opacity: 0.95

      Rectangle {
        x: parent.width * 0.16
        y: parent.height * 0.14
        width: parent.width * 0.36
        height: parent.height * 0.34
        radius: height / 2
        rotation: -20
        color: "#ffffff"
        opacity: racer.wrecked ? 0 : 0.75
      }
    }
  }

  // ------------------------------------------------------------------ chrome

  // Gold, silver, bronze for the top three — drawn rather than emoji, same
  // as everything else on this board, so a medal reads as part of the same
  // object language as the coins and cars sitting next to it instead of a
  // borrowed system glyph in a different style entirely.
  component Medal: Rectangle {
    id: medal
    property int rank: 1
    readonly property color tone: rank === 1 ? "#fbbf24" : rank === 2 ? "#cbd5e1" : "#c2703d"

    width: Style.space(26)
    height: width
    radius: width / 2
    color: root.mix(tone, "#000000", 0.20)
    border.width: Math.max(1, Style.space(2))
    border.color: root.core(tone)

    // The same official Omarchy mark the omacoins carry, struck into the
    // medal the same way (colorized to a darkened cut of its own metal) so
    // a medal reads as "an omacoin, just gold/silver/bronze" rather than a
    // separate badge language with its own rank digit.
    Image {
      id: medalMark
      anchors.centerIn: parent
      width: medal.width * 0.62
      height: width
      source: root.omarchyIcon
      fillMode: Image.PreserveAspectFit
      sourceSize.width: 96
      sourceSize.height: 96
      smooth: true
      visible: false
    }
    MultiEffect {
      anchors.fill: medalMark
      source: medalMark
      colorization: 1.0
      colorizationColor: root.mix(medal.tone, "#000000", 0.55)
    }
  }

  // A key, drawn as a key. The status line used to be one run-on sentence of
  // words and interpuncts, which is legible but says "prose" when what it is
  // is a control reference.
  component Cap: Rectangle {
    id: cap
    property alias text: capText.text

    implicitWidth: Math.max(capText.implicitWidth + Style.spacing.sm * 2, Style.space(15))
    implicitHeight: capText.implicitHeight + Style.spacing.xxs * 2
    radius: Math.max(2, Style.space(3))
    color: root.fade(root.foreground, 0.07)
    border.width: 1
    border.color: root.fade(root.foreground, 0.22)

    Text {
      id: capText
      anchors.centerIn: parent
      color: root.mix(root.background, root.foreground, 0.78)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
    }
  }

  component Hint: Row {
    id: hint
    property var keys: []
    property string label: ""

    spacing: Style.spacing.xxs

    Repeater {
      model: hint.keys
      Cap {
        anchors.verticalCenter: hint.verticalCenter
        text: modelData
      }
    }
    Text {
      anchors.verticalCenter: hint.verticalCenter
      leftPadding: Style.spacing.xxs
      text: hint.label
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
  }
}
