sub f { $_[0]++ } my $s = ""; for my $i (1..3) { f($i); f($i); $s .= $i } print "$s\n";
