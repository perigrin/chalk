our $g = 0; sub bump { $g++ } my $s = ""; for (1..3) { $s .= $g; bump() } print "$s$g\n";
