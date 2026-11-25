my @a=(1,2); sub f { my @l=@_; $_++ for @_; "@l" } print f(@a), "@a\n";
