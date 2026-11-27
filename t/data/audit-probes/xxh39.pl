sub f { my ($x, %o) = @_; $o{k} = 0; $_[2] } print f(1, k => 5), "\n";
