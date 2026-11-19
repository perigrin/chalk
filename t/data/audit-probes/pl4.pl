our $g = 0; sub bump { $g += 10 } my $i = 0; while ($i < 3) { $i++; $g = $g + 1; bump(); } print "$g\n";
