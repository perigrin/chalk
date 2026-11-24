our $n=0; sub f { local $SIG{__DIE__}=sub { $n++ }; die "x\n" } eval { f() }; eval { die "y\n" }; print "$n\n";
