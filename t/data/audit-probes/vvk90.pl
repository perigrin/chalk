my @q = (1, 2, 3); my $n = 0; for my $i (0..$#q) { $n += $q[$i]; pop @q if $i == 0 } print "$n", scalar(@q), "\n";
