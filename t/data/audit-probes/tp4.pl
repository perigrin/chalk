our $g = 0; sub bump { $g += 10 } my $i = 0; while ($i < 2) { $i++; my $b = $g; bump(); print $g - $b } print "\n";
