our $x = 1; my $y = 5; *x = \$y; eval { $x++; die "z\n" }; print "$y\n";
