my @a=(1,2,3); sub g { "@_" } print g(@a[0,1], $a[0]=9), "\n";
