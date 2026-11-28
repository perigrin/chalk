my $n = 3; my $c = sub { $n-- }; my $k = 0; while ($n > 0) { $c->(); $k++ } print "$k\n";
