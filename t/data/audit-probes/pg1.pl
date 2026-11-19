our $g = 0; sub bump { $g += 10 } for my $i (1..3) { $g = $g + 1; bump(); } print "$g\n";
