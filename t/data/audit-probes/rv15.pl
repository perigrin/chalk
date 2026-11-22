sub f { my ($c, %o) = @_; $o{z} = 1; my %k = %o; $o{w} = 2; return join(",", sort keys %k) } print f(0, a => 1), "\n";
