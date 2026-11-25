my @a=(1,2); sub f { my @l=@_; @l=reverse @l; "@l@_" } print f(@a), "@a\n";
