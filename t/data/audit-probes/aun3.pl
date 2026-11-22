our @g=(0); sub bump { $g[0] += 10 } for my $i (1..3) { $g[0] = $g[0]+1; bump(); } print "@g\n";
