our %g = (a => 1); print %g ? "t" : "f"; delete $g{a}; print %g ? "t" : "f", "\n";
