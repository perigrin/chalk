my @a=(1,2); sub f { my @l=@_; push @a,3; scalar(@l) } print f(@a), "\n";
