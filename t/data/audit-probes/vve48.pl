my $x = 1; sub f { @_[0,1] = (5, 6); $_[0] } my $y = 2; print f($x, $y), "$x$y\n";
