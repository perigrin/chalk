our $d = 0; sub f { my ($n) = @_; local $d = $d + 1; $n ? f($n - 1) : $d } print f(3), $d, "\n";
