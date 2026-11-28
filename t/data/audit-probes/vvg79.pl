my $n = 0; my $c = sub { $n++ }; my $k = 0; for (1..3) { $k += $n; $c->() } print "$k\n";
