include <common.scad>
bevel_gear(circ_pitch=CIRC_PITCH, teeth=T_GEAR, mate_teeth=T_PINION,
           shaft_diam=SHAFT_DIAM, cutter_radius=0, spiral=0, right_handed=true,
           backing=BACKING, cone_backing=false, $fn=64);
