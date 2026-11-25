my @a=(1,2); sub f { unshift @a, 0; "@_" } print f(@a), "\n";
