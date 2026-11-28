sub f { $_[0]++ } my $s = ""; for my $i (1..3) { my $x; f($x); $s .= $x } print "$s\n";
