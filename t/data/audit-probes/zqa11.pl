my @a=(1,2); sub f { my $n=@_; my @l=@_; $_[1]=9; "$n@l" } print f(@a), "\n";
