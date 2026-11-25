our $g=1; sub a1 { local $g=2; b1() } sub b1 { local $g=3; die "d\n" } eval { a1() }; print "$g\n";
