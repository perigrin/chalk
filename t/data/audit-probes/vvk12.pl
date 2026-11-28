sub f { my ($x, $y) = @_; $y //= 5; $x + $y } print f(1), f(1, 2), f(1, undef), "\n";
