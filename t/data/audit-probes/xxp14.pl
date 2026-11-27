my @a = (1,2,3); sub fst { $_[0] } print fst(@a[1,2] = (8,9)), "\n";
