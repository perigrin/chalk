my @a=(1,2); sub g { $a[0]=9 } sub f { my @l=@_; g(); "@l" } print f(@a), "\n";
