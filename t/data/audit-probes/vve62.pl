my $x = 1; sub f { my @c = @_; $c[0]++; $_[0] } print f($x), "$x\n";
