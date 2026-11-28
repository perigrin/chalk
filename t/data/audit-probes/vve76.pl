my $x = 1; sub f { $x = 5; my @m = map { $_ * 2 } @_; "@m" } print f($x), "\n";
