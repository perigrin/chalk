sub f { my ($x, $y) = @_; $y //= 10; return $x + $y } print f(1), " ", f(1, 2), "\n";
