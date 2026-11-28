our $g = 1; eval { local $g = 2; eval { local $g = 3; die "x\n" }; print $g; }; print "$g\n";
