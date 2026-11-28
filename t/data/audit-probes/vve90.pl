my @a = (1,2); sub f { push @a, 3; $_[0] } print f($a[0]), "\n";
