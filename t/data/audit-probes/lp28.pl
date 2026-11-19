my @m = ([1,2],[3,4]); my $s = 0; for my $r (@m) { for my $c (@$r) { $s += $c; $c = 0 } } print "$s $m[1][1]\n";
