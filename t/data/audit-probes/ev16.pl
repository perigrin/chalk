my $x = 1; eval { $x = 2 }; print "$x\n"; my $y = 1; eval { die "a\n"; $y = 2 }; print "$y\n";
