my @l = (); our %h; print((%h = @l) ? "t" : "f", "\n"); @l = (1, 2, 1, 3); if (%h = @l) { print "y ", scalar(keys %h), "\n" } print !(%h = ()) ? "empty" : "full", "\n";
