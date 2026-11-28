our $x = 1; sub f { map { $_ = 5 } $x; $_[0] } print f($x), "\n";
