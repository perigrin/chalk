our $x=1; sub f { local $x=2; die "d\n" } eval { f() }; print $@, $x, "\n";
