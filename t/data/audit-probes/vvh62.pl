my $x = 1; my $z = 0; my @l; eval { @l = ($x = 2, 1 / $z) }; print "$x", scalar(@l), "\n";
