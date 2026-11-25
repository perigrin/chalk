my @a=(1,2); sub f { my @l=(0,@_); $a[0]=9; "@l" } print f(@a), "\n";
