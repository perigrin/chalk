our $g = 1; eval { local $g = 2; eval { local $g = 3; die "a\n" }; die "b$g\n" }; print $@, $g, "\n";
