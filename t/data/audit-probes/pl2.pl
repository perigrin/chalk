my $c = 0; my $b = sub { $c += 10 }; for my $i (1..3) { $c = $c + 1; $b->(); } print "$c\n";
