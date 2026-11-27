sub f { my ($x) = @_; my ($y) = @_; $_[0] = 5; my ($z) = @_; "$x$y$z" } my $v = 1; print f($v), "\n";
