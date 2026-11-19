our $g = 0; sub rd { $g } my $s = 0; for my $i (1..3) { $g = $g + $i; $s += rd(); } print "$s\n";
