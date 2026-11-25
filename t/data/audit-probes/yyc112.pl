my @a=(1); sub f { "@_" } print f($a[0]=5, $a[0]=7), "\n";
