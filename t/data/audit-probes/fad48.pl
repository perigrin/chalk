our $g=1; sub f { local $g = 2; g2(); } sub g2 { $g = 3; die "x\n" } eval { f() }; print "$g\n";
