sub f { $_[0]++ } my $t = 0; my $i = 0; while ($i++ < 3) { my $y = $i; f($y); $t += $y } print "$t\n";
