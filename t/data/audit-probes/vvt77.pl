sub f { $_[0]++ } my $t = 0; for my $i (1..3) { my @y = ($i); f($y[0]); $t += $y[0] } print "$t\n";
