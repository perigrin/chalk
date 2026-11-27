our $g = 0; sub bump { $g++ } my $s = ""; for (1..3) { my $o = $g; bump(); $s .= "$o$g" } print "$s\n";
