our $g=1; our $k=1; sub h { local $k=5; die "x\n" } sub f { local $g=2; h(); } eval { f() }; print "$g$k\n";
