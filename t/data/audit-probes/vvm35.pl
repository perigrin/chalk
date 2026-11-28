our @a = (1,2,3); sub f { local @a = (@_); push @a, 0; scalar(@a) } print f(1), f(1, 2), scalar(@a), "\n";
