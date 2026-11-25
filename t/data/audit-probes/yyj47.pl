our $g=1; sub t { local $g = 2; my $i = 0; while (1) { local $g = $g + 1; last if ++$i > 2 } $g } print t(), $g, "\n";
