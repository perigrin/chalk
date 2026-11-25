our $g=1; eval { if (1) { local $g=2; die "x\n" } }; print "$g\n";
