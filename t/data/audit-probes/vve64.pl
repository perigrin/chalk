my $x = 1; sub f { $x = 5; my ($v) = @_; $v } print f($x), "\n";
