our $g=1; sub f { local $g=2; eval { die "in\n" }; die "out:$@" } eval { f() }; print "$g $@";
