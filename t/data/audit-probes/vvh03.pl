my $x = 1; eval { $x = 2; die "z\n"; $x = 3 }; print "$x\n";
