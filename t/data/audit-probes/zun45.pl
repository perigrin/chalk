our $g=1; eval { local $g=2; eval { local $g=3; die "a\n" }; print $g; die "b\n" }; print "$g\n";
