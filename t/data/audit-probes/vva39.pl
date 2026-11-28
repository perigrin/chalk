our $x = 1; sub f { local $x = 2; g() } sub g { die "z$x\n" } eval { f() }; print "$x$@";
