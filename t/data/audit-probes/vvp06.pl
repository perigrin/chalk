my @a = (1,2); sub f { $a[$#a] = 5; $_[0] } print f($a[1]), "\n";
