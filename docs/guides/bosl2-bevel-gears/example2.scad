// BOSL2 `bevel_gear()` Example 2, as the reference side of
// docs/guides/bosl2-bevel-gears.md. The two gears are gears.scad:2405-2414 verbatim, with
// only the two `color()` calls parameterised.
//
// BOSL2 is BSD-2-Clause, Copyright 2017-2019 Revar Desmera.
// https://github.com/BelfrySCAD/BOSL2

include <BOSL2/std.scad>
include <BOSL2/gears.scad>

// BOSL2's own example paints the pinion "lightblue" and leaves the gear the default yellow.
// `occtkit render-preview` paints every input body one colour, so the committed reference
// render overrides both to that colour and the side-by-side compares geometry, not palette.
// Restore BOSL2's own look with:
//   -D 'pinion_color="lightblue"' -D 'gear_color=[0.976,0.843,0.173]'
pinion_color = [0.70, 0.70, 0.75];
gear_color   = [0.70, 0.70, 0.75];

t1 = 16; t2 = 28;
color(pinion_color)bevel_gear(
    circ_pitch=5, teeth=t1, mate_teeth=t2,
    slices=12, anchor="apex", orient=FWD
);
color(gear_color)bevel_gear(
    circ_pitch=5, teeth=t2, mate_teeth=t1, right_handed=true,
    slices=12, anchor="apex", backing=3, spin=180/t2
);
