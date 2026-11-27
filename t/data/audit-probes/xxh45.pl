sub f { my ($n) = @_; $n > 0 ? $n + f($n - 1) : 0 } my $x = 3; print f($x), $x, "\n";
