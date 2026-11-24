eval { die "a\n" }; { local $@; eval { die "b\n" }; } print $@;
