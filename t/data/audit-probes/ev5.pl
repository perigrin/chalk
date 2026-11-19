my $i = 0; for my $k (1..3) { eval { $i += $k; die "x\n" if $k == 2; $i += 10 } } print "$i\n";
