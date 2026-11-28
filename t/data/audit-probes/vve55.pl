my $x = 1; sub f { shift; $_[0]++ } my $y = 2; f($x, $y); print "$x$y\n";
