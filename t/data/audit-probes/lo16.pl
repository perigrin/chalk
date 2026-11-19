our $v = 1; sub show { print $v } sub t { local $v = 2; show(); eval { local $v = 3; show(); die "x\n" }; show() } t(); show(); print "\n";
