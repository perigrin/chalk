my @a=(1); sub f { "@_" } print f($a[0], $a[0]++), "\n";
