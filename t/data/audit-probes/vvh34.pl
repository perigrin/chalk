eval { die "x\n" }; { local $@; eval { die "y\n" } } print $@;
