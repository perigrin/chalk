our $g = 1; sub d { die "d\n" } sub f { local $g = 2; d() } eval { f() }; print $g, $@;
