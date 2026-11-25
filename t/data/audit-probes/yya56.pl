my @a=(1,2); sub f { my ($p,@r)=@_; push @a, 3; $_[1]=9; "$p@r @a" } print f(@a), "\n";
