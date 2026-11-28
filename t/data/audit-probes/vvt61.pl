my @a = (1,2,3); sub f { $_[0]++ } my $t = 0; for my $x (@a) { my $y = $x * 2; f($y); $t += $y } print "$t|@a\n";
