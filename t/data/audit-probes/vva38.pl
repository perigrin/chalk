our $x = 1; sub f { local $x = 2; die "z\n" } eval { f() }; print "$x$@";
