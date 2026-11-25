my @a=(1,2); sub f { $a[1]=9; $_[1] } print f(@a), "\n";
