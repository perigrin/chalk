sub f { my ($a1, $b1) = @_; $a1++; $_[1]++ } my ($x, $y) = (1, 1); f($x, $y); print "$x$y\n";
