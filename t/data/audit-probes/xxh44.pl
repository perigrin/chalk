sub f { my ($n, $acc) = @_; return $acc unless $n; f($n - 1, $acc + $n) } print f(4, 0), "\n";
