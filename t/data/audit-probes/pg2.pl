our $g = 0; my $s = ""; sub bump { $g += 10 } for my $i (1..3) { $g = $g + 1; bump(); $s .= "$g," } print "$s\n";
