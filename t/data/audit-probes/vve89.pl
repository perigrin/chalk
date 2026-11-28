my @a = (1,2); sub f { $_ = 5 for @a; $_[0] } print f($a[0]), "\n";
