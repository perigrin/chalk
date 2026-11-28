sub f { $_[0]++ } my $t = 0; for my $i (1..2) { for my $j (1..2) { my $y = $i * $j; f($y); $t += $y } } print "$t\n";
