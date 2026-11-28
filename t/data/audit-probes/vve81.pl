my @a = (1,2); sub f { $a[0] = 5; $_[0] } print f($a[0]), "\n";
