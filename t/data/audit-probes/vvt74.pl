sub f { $_[0]++ } my $t = 0; for my $i (1..3) { my $y = $i; f($y) if $i % 2; $t += $y } print "$t\n";
