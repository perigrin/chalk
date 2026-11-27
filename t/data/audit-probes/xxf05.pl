our $g = 1; for my $i (1..3) { local $g = $g + $i; print $g } print $g, "\n";
