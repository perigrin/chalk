our $g = 1; eval { local $g = 2; die "x\n" }; print "$g\n";
