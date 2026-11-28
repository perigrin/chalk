my $x = 1; sub f { $x = 5; my @v = @_; $v[0] } print f($x), "\n";
