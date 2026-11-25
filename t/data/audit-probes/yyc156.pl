my @a=(1,2,3); sub f { "@_" } print f(@a, $a[0]=9), "\n";
