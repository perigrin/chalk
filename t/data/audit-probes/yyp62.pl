my @a=(1,2); sub f { unshift @a, 0; $_[0]=9; "@a" } print f(@a), "\n";
