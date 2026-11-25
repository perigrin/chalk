my @a=(1,2); sub f { splice(@a, 1, 0, 5); "@_" } print f(@a), "\n";
