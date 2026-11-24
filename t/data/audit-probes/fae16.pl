eval { die "a\n" }; eval { die $@ . "b\n" }; print $@;
