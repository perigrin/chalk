our $g=1; sub f { local $g=2; die "x\n" if $_[0]; 1 } eval { f(1) }; print "$g\n";
