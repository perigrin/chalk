our $x=1; eval { $x=2; die "a\n" }; my $y=$x; eval { $x=3; die "b\n" }; print "$y$x\n";
