my @a=(1,2); sub f { unshift @a, 0; $_[1] } print f(@a), "\n";
