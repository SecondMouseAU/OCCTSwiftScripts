include <common.scad>
bevel_gear(circ_pitch=CIRC_PITCH, teeth=T_PINION, mate_teeth=T_GEAR,
           shaft_diam=SHAFT_DIAM, cutter_radius=0, spiral=0,
           backing=BACKING, cone_backing=false, $fn=64);
