our @a=(1,2); sub f { $a[0]=9; my @l=@_; "@l" } print f(@a), "\n";
