our $x = 1; my $y = 5; eval { *x = \$y; die "z\n" }; $x++; print "$y\n";
