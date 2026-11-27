our $g = 0; sub bump { $g++ } my $i = 0; while ($i < 3) { bump(); $i += $g } print "$g$i\n";
