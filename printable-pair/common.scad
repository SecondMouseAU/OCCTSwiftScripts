// Printable straight-bevel pair, 90 degree shaft angle.
// Reference side, generated with BOSL2 (BSD-2-Clause, Copyright 2017-2019 Revar Desmera).
//
// Design constraints (OCCTSwiftScripts bevel gear port test):
//   pinion max diameter 12 mm, gear max diameter 24 mm, 3 mm axle both.
//
// face_width is left at BOSL2's default (ocone_rad/3) so the pair has real bevel
// proportions. An earlier revision shortened it to force 2 mm of root thickness at
// the inner end of the tooth; that met the number and turned the pair into what read
// as crown gears, because the teeth became a thin band on the rim of a flat blank.
// Bevel teeth taper toward the apex by construction, so the inner end is always
// thinner: 2.149 mm at the outer root, 1.433 mm at the inner.
include <BOSL2/std.scad>
include <BOSL2/gears.scad>

CIRC_PITCH = 4.289422740;   // module 1.365365664
T_PINION   = 7;
T_GEAR     = 14;
SHAFT_DIAM = 3.0;
BACKING    = 0.0;   // matched to the OCCTSwift side, which cannot union a backing disc here
