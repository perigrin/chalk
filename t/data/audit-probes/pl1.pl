my $c = 0; sub bump { $c += 10 } for my $i (1..3) { $c = $c + 1; bump(); } print "$c\n";
