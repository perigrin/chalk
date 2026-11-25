my @a=(1,2); sub f { my @l=@_[0,1]; $a[0]=9; "@l" } print f(@a), "\n";
