our $g=1; my $x=0; eval { local $g=2; $x=$g; die "x\n" }; print "$g$x\n";
