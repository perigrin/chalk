our $g = 0; sub bump { $g += 10 } for my $i (1..2) { for my $j (1..2) { $g = $g + 1; bump() } } print "$g\n";
