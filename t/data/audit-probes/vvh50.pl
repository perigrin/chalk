my $x = 1; eval { my $x = 2; die "z\n" }; print "$x\n";
