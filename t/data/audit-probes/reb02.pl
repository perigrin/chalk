our $g=1; sub f { local $g=2; h() } sub h { die "x\n" } eval { f() }; print "$g $@";
