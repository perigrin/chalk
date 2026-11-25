my @a=(1,2); sub f { my @l=@_; $_[0]=9; "@l" } print f(@a), "\n";
