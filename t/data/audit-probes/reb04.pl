our $g=1; eval { eval { local $g=2; die "in\n" }; print "$g $@"; local $g=3; die "out\n" }; print "$g $@";
