our $g = 1; sub a { local $g = 2; b() } sub b { local $g = 3; die "x\n" } eval { a() }; print $g, $@;
