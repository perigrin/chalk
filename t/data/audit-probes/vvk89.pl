my @q = (1, 2, 3); my $n = 0; $n += shift @q while @q; print "$n", scalar(@q), "\n";
