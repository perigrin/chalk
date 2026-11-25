our $g=1; sub f { local $g=2; die "x\n" } eval { eval { f() }; print $g; f() }; print "$g\n";
