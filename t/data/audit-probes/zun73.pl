our $g=1; eval { local $g=2; die "x\n" if $g==2; }; eval { local $g=3; }; print "$g\n";
