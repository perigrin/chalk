my ($p,$q)=(1,2); for my $i (0..3) { ($i % 2 ? $p : $q) += $i } print "$p $q\n";
