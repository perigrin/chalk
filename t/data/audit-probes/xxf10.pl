our $g = 1; sub rd { $g } eval { local $g = 2; eval { local $g = 3; die "in\n" }; print rd(), $@; die "out\n" }; print rd(), $@;
