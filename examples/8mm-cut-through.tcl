#!/usr/bin/env tclsh
lappend auto_path [file dirname [pwd]];
package require tclgcode;

use_millimetres;
use_absolute_positioning;
select_coordinate_system "XY"; # select the XY plane as the default coordinate system;
set_feedrate_timebase "minutes"; # set feed rate mode to units per minute;
set_arc_tolerance_mm 0.2; # 0.2 mm arc tolerance.

# Initial position above workpiece
rapid_linear_move Z 5; # Move to a safe height above the workpiece
rapid_linear_move X -3.825 Y 0; # Move to the starting position (4mm radius from center)

spindle_clockwise 3000; # Start spindle clockwise (adjust spindle speed as necessary                                          
dwell 1;
spindle_clockwise 6000; 
dwell 1;
spindle_clockwise 10000; 

set depth -7.2;

set bitdiameter [expr {25.4*1.0/8.0}]; # 1/8 inch bit - in mm;
set motor_hole_radius [expr {3.0*25.4/2.0}]; # 2.5 inch diameter hole
set motor_bolt_hole_radius [expr {9.0/2}]; # 9mm hole;
set motor_bolt_hole_offset [expr {$motor_hole_radius+5}];

cut_hole_with_radius 0.0 0.0 $motor_hole_radius $depth $bitdiameter;
# Cut the four holes around the motor;
set d $motor_bolt_hole_offset;
cut_hole_with_radius $d $d $motor_bolt_hole_radius $depth $bitdiameter;
cut_hole_with_radius -$d $d $motor_bolt_hole_radius $depth $bitdiameter;
cut_hole_with_radius -$d -$d $motor_bolt_hole_radius $depth $bitdiameter;
cut_hole_with_radius $d -$d $motor_bolt_hole_radius $depth $bitdiameter;

# Cut the slotted holes for the plate-mounting bolts;
set slop 15.0;
set angle90 90.0;

set bolt_hole_radius [expr {9.0/2}];
set y_top [expr {-4*25.4/2}];
set y_bottom [expr {$y_top-40}]; # 40mm below other holes
set x_left [expr {-2.5*25.4}];
set x_right [expr {-1*$x_left}];

cut_rounded_slot_radius_slop $x_left $y_top $bolt_hole_radius $slop $depth $bitdiameter $angle90;
cut_rounded_slot_radius_slop $x_right $y_top $bolt_hole_radius $slop $depth $bitdiameter $angle90;
cut_rounded_slot_radius_slop $x_left $y_bottom $bolt_hole_radius $slop $depth $bitdiameter $angle90;
cut_rounded_slot_radius_slop $x_right $y_bottom $bolt_hole_radius $slop $depth $bitdiameter $angle90;

# Finish at a safe height;
rapid_linear_move Z 10.0; # Move to a safe height above the workpiece
# Stop the spindle
spindle_off;
# Move to origin;
rapid_linear_move X 0.0 Y 0.0;
# end the CNC job
end_job;
