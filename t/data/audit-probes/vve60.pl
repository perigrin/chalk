my $x = 1; sub f { splice(@_, 0, 1); $_[0]++ } my $y = 2; f($x, $y); print "$x$y\n";
