// BOSL2 `bevel_gear()` Example 3, as the reference side of
// docs/guides/bosl2-bevel-gears.md. The two gears are gears.scad:2415-2430 verbatim, with
// only the two `color()` calls parameterised. BOSL2 renders this as a four-frame animation;
// `$t` is 0 in a plain render, which is the frame reproduced on the OCCTSwift side.
//
// BOSL2 is BSD-2-Clause, Copyright 2017-2019 Revar Desmera.
// https://github.com/BelfrySCAD/BOSL2

include <BOSL2/std.scad>
include <BOSL2/gears.scad>

// See example2.scad for why both colours are overridden to one value here.
pinion_color = [0.70, 0.70, 0.75];
gear_color   = [0.70, 0.70, 0.75];

t1 = 14; t2 = 28; circ_pitch=5;
color(pinion_color)back(pitch_radius(circ_pitch, t2)) {
  yrot($t*360/t1)
  bevel_gear(
    circ_pitch=circ_pitch, teeth=t1, mate_teeth=t2, shaft_diam=5,
    slices=12, orient=FWD
  );
}
color(gear_color)down(pitch_radius(circ_pitch, t1)) {
  zrot($t*360/t2)
  bevel_gear(
    circ_pitch=circ_pitch, teeth=t2, mate_teeth=t1, right_handed=true,
    shaft_diam=5, slices=12, backing=3, spin=180/t2, cone_backing=false
  );
}
