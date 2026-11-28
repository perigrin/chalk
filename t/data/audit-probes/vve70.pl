my $x = 1; sub f { $x = 5; return @_ } print f($x), "\n";
