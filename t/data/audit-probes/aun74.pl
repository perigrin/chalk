our $g=1; for my $i (1..3) { local $g = $g + 1; next if $i == 2; print $g } print " $g\n";
