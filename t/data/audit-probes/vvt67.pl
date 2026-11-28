sub f { $_[0]++ } my $t = 0; for (my $i = 0; $i < 3; $i++) { my $y = $i; f($y); $t += $y } print "$t\n";
