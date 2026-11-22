our $g = 0; sub bump { $g += 10 } my $i = 0; while ($i++ < 3) { $g = $g + 1; bump() if $i > 1 } print "$g\n";
