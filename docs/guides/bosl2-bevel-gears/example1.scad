// BOSL2 `bevel_gear()` Example 1, as the reference side of
// docs/guides/bosl2-bevel-gears.md. The gear itself is gears.scad:2400-2404 verbatim.
//
// BOSL2 is BSD-2-Clause, Copyright 2017-2019 Revar Desmera.
// https://github.com/BelfrySCAD/BOSL2
//
// Render (see the page for the camera derivation):
//   openscad -o example1-bosl2.png --imgsize=2400,1800 --projection=p \
//       --colorscheme=Tomorrow --camera=<eye>,<target> example1.scad
// Mesh for the numeric comparison:
//   openscad -o example1.stl example1.scad

include <BOSL2/std.scad>
include <BOSL2/gears.scad>

// `occtkit render-preview` paints every input body one colour, so the reference render is
// generated with a matching one. Drop the `color()` (or override with -D) for BOSL2's own.
gear_color = [0.70, 0.70, 0.75];

color(gear_color)
bevel_gear(
    circ_pitch=5, teeth=36, mate_teeth=36,
    shaft_diam=5, spiral=0
);
