sub f { $_[0]++ } my $t = 0; for my $i (1..3) { my ($y, $z) = ($i, $i); f($y); f($z); f($z); $t += $y * $z } print "$t\n";
