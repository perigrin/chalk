sub f { $_[0]++ } my $t = 0; for my $i (1..3) { my $y = $i; if ($i % 2) { f($y) } $t += $y } print "$t\n";
