our $g = 1; eval { $g = 2; die "x\n"; $g = 3 }; print "$g\n";
