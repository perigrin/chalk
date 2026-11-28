my @keep; our @a = (1,2,3); for my $i (1..2) { local @a = ($i); push @a, 0; push @keep, scalar(@a) } print "@keep|@a\n";
