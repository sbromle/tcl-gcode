# tclgcode - a DSL implemented in Tcl to help make generation of GRBL-compatible
# gcode easier;
package provide tclgcode 1.0;

set ::feedrate 0;

proc use_millimetres {} {
	puts "G21 ; Set units to millimetres"
}

proc use_inches {} {
	puts "G20 ; Set units to inches"
}

proc use_absolute_positioning {} {
	puts "G90 ; Use absolute positioning"
}

proc use_relative_positioning {} {
	puts "G91 ; Use relative positioning"
}

proc select_coordinate_system {spec} {
	switch $spec {
		"XY" {
			puts "G17 ; select xy plane"
		}
	}
	return;
}

proc set_feedrate_timebase {tb} {
	switch $tb {
		"minutes" {
			set g "G94; Set feed rate mode to units per minute";
		}
	}
	puts "$g";
}

proc set_arc_tolerance_mm {mm} {
	puts "\$12 $mm ; set arc tolerance to $mm mm";
}

proc _check_move_args {adict} {
	if {[llength $adict]%2 != 0} {
		return -code error "rapid_move: args must be key value pairs for keys E,F,S,X,Y,Z - each optional"
	}
}

proc _get_move_args {adict} {
	set cmd {};
	foreach key {X Y Z E F S} {
		if {[dict exists $adict $key]} {
			set val [dict get $adict $key];
			if {[string is double -strict $val]} {
				lappend cmd "${key}${val}"
			}
		}
	}
	return $cmd;
}

proc rapid_linear_move {args} {
	_check_move_args $args;
	set cmd [_get_move_args $args];
	if {[llength $cmd]>0} {
		puts "G0 [join $cmd " "] ; rapid linear move";
	}
}

proc linear_move {args} {
	_check_move_args $args;
	set cmd [_get_move_args $args];
	if {[llength $cmd]>0} {
		puts "G1 [join $cmd " "] ; linear move";
	}
}

proc finish_moves {} {
	puts "M400 ; dwell until all moves are finished";
}

proc dwell {floatseconds} {
	if {![string is double -strict $floatseconds]} {
		return -code error "dwell takes a real number of seconds";
	} elseif {$floatseconds<0} {
		return -code error "dwell waits for positive time only";
	} elseif {$floatseconds == 0.0} {
		# Then this is treated the same as "finish_moves";
		tailcall finish_moves;
	}
	set cmd {};
	set seconds [expr {int($floatseconds)}];
	set ms [expr {int(1000*($floatseconds-$seconds))}];
	if {$ms>0} {
		puts "G4 P$ms ; dwell for $ms milliseconds";
	}
	while {$seconds>=1} {
		# Done this way because GRBL doesn't seem to like using "G4 S1" for example;
		puts "G4 P1000 ; dwell for 1 second";
	}
}

# Speed is in units of whatever "CUTTER_POWER_UNIT" was set to;
proc spindle_clockwise {speed} {
	if {![string is integer -strict $speed] || $speed <0} {
		return -code error "spindle_clockwise: Speed must be a positive integer";
	}
	puts "M4 S[string trim $speed]";
}

proc spindle_on {} {
	puts "M4 0 ; start the spindle";
}

proc spindle_off {} {
	puts "M5 ; stop the spindle";
}

proc end_job {} {
	puts "M30 ; End program";
}

proc _parse_arc_args {alist} {
	if {[llength $alist]%2 != 0} {
		return -code error "arc - invalid args '$alist' must be key value list";
	}
	set cmd {};
	set hasIorJ 0;
	set hasR 0;
	foreach key {X Y Z I J R F} {
		if {[dict exists $alist $key]} {
			if {$key eq "I"} {
				set hasIorJ 1;
			}
			lappend cmd "${key}[dict get $alist $key]";
		}
	}
	if {$hasIorJ == 0 && $hasR == 0} {
		return -code error "arcs must have I and J, or must have R.";
	} elseif {$hasIorJ ==1 && $hasR == 1} {
		return -code error "arcs must use IJ form or the R form.";
	}
	return $cmd;
}

proc _arc {dir dictargs} {
	set cmd [_parse_arc_args $dictargs];
	if {[llength $cmd]==0} return;
	if {$dir eq "CW"} {
		set g "G2";
	} else {
		set g "G3";
	}
	puts "$g [join $cmd " "] ; arc";
}

proc clockwise_arc {args} {
	tailcall _arc "CW" $args;
}

proc counterclockwise_arc {args} {
	tailcall _arc "CCW" $args;
}

proc cut_hole_with_radius {cx cy radius depth bitdiameter {feedrate 5} {zinc -0.2}} {
	if {$zinc>=0.0} {
		set zinc -0.2; # safety check for bad zinc;
	} elseif {$zinc < -1.0} {
		set zinc -1.0; # safety check for too aggressive zinc;
	}
	if {$depth<0} {
		set bottom $depth;
	} else {
		set bottom [expr {-1*$depth}];
	}

	if {$feedrate <= 0 } {
		set feedrate 5.0;
	} elseif {$feedrate > 40} {
		set feedrate 40.0;
	}

	set zpos 0.0;
	set px(0) $cx;
	set py(0) [expr {$cy+$radius-$bitdiameter/2.0}];

	set px(1) [expr {$cx+$radius-$bitdiameter/2.0}];
	set py(1) $cy;

	set px(2) $cx;
	set py(2) [expr {$cy-$radius+$bitdiameter/2.0}];

	set px(3) [expr {$cx-$radius+$bitdiameter/2.0}];
	set py(3) $cy;

	rapid_linear_move Z 5; # Move to a safe height above the workpiece
	rapid_linear_move X $px(3) Y $py(3);
	while {$zpos>$bottom} {
		set zpos [expr {$zpos+$zinc}];
		linear_move Z $zpos F 20;
		set oldpx $px(3);
		set oldpy $py(3);
		for {set i 0} {$i<4} {incr i} {
			clockwise_arc X $px($i) Y $py($i) I [expr {$cx-$oldpx}] J [expr {$cy-$oldpy}] F $feedrate;
			set oldpx $px($i);
			set oldpy $py($i);
		}
	}
	rapid_linear_move Z 5; # Move back to a safe height above the workpiece
}

proc _get_circle_standard_points {cx cy radius bitdiameter} {
	set pts {};
	set px(0) $cx;
	set py(0) [expr {$cy+$radius-$bitdiameter/2.0}];
	lappend pts $px(0) $py(0);

	set px(1) [expr {$cx+$radius-$bitdiameter/2.0}];
	set py(1) $cy;
	lappend pts $px(1) $py(1);

	set px(2) $cx;
	set py(2) [expr {$cy-$radius+$bitdiameter/2.0}];
	lappend pts $px(2) $py(2);

	set px(3) [expr {$cx-$radius+$bitdiameter/2.0}];
	set py(3) $cy;
	lappend pts $px(3) $py(3);
}

proc _midpoint {p0x p0y p1x p1y} {
	set mx [expr {0.5*($p0x+$p1x)}];
	set my [expr {0.5*($p0y+$p1y)}];
	return [list $mx $my];
}

proc rotate_point {px py cx cy angle_degrees} {
	set c [expr {cos($angle_degrees*3.14159265358979/180.0)}];
	set s [expr {sin($angle_degrees*3.14159265358979/180.0)}];
	if {abs($c)<1.0E-5} {
		set c 0.0;
		if {$s<0.0} {
			set s -1.0;
		} else {
			set s 1.0;
		}
	} elseif {abs($s)<1.0E-5} {
		set s 0.0;
		if {$c<0.0} {
			set c -1.0;
		} else {
			set c 1.0;
		}
	}
	set rx [expr {$px-$cx}];
	set ry [expr {$py-$cy}];
	set nrx [expr {$c*$rx-$s*$ry}];
	set nry [expr {$s*$rx+$c*$ry}];
	set nx [expr {$cx+$nrx}];
	set ny [expr {$cy+$nry}];
	return [list $nx $ny];
}

proc cut_rounded_slot_radius_slop {cx cy radius slop depth bitdiameter {angle_degrees 0.0} {feedrate 5} {zinc -0.2}} {
	if {$zinc>=0.0} {
		set zinc -0.2; # safety check for bad zinc;
	} elseif {$zinc < -1.0} {
		set zinc -1.0; # safety check for too aggressive zinc;
	}
	if {$depth<0} {
		set bottom $depth;
	} else {
		set bottom [expr {-1*$depth}];
	}
	if {$feedrate <= 0 } {
		set feedrate 5.0;
	} elseif {$feedrate > 40} {
		set feedrate 40.0;
	}

	if {$slop<0.0} {
		set slop 0.0;
	}

	lassign [ _get_circle_standard_points $cx $cy $radius $bitdiameter] cpx(0) cpy(0) cpx(1) cpy(1) cpx(2) cpy(2) cpx(3) cpy(3);

	# Add the slop in the x-direction (user can change angle);
	# Once slop goes in, we actually split the circle into two
	# halfs, so we introduce the new points here too;
	set px(0) [expr {$cpx(0)+0.5*$slop}];
	set py(0) $cpy(0);
	set px(1) [expr {$cpx(1)+0.5*$slop}];
	set py(1) $cpy(1);
	set px(2) [expr {$cpx(2)+0.5*$slop}];
	set py(2) $cpy(2);

	set px(3) [expr {$cpx(2)-0.5*$slop}];
	set py(3) $cpy(2);
	set px(4) [expr {$cpx(3)-0.5*$slop}];
	set py(4) $cpy(3);
	set px(5) [expr {$cpx(0)-0.5*$slop}];
	set py(5) $cpy(0);

	# Get the midpoints of the top and bottom arcs;
	lassign [_midpoint $px(0) $py(0) $px(2) $py(2)] mx(0) my(0);
	lassign [_midpoint $px(3) $py(3) $px(5) $py(5)] mx(1) my(1);

	# Rotate all points by the specified angle;
	for {set i 0} {$i<6} {incr i} {
		lassign [rotate_point $px($i) $py($i) $cx $cy $angle_degrees] px($i) py($i);
	}
	lassign [rotate_point $mx(0) $my(0) $cx $cy $angle_degrees] mx(0) my(0);
	lassign [rotate_point $mx(1) $my(1) $cx $cy $angle_degrees] mx(1) my(1);

	rapid_linear_move Z 5; # Move to a safe height above the workpiece
	rapid_linear_move X $px(0) Y $py(0);
	set zpos 0.0;
	while {$zpos>$bottom} {
		set zpos [expr {$zpos+$zinc}];
		linear_move Z $zpos F 20;
		# First two quadrants;
		clockwise_arc X $px(1) Y $py(1) I [expr {$mx(0)-$px(0)}] J [expr {$my(0)-$py(0)}] F $feedrate;
		clockwise_arc X $px(2) Y $py(2) I [expr {$mx(0)-$px(1)}] J [expr {$my(0)-$py(1)}] F $feedrate;
		# First side;
		linear_move X $px(3) Y $py(3);
		# Last two quadrants;
		clockwise_arc X $px(4) Y $py(4) I [expr {$mx(1)-$px(3)}] J [expr {$my(1)-$py(3)}] F $feedrate;
		clockwise_arc X $px(5) Y $py(5) I [expr {$mx(1)-$px(4)}] J [expr {$my(1)-$py(4)}] F $feedrate;
		# Last side
		linear_move X $px(0) Y $py(0);
	}
	rapid_linear_move Z 5; # Move back to a safe height above the workpiece
}
