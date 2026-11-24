our $g=1; sub h { die "x\n" } sub f { local $g=2; h() } eval { f() }; print "$g\n";
