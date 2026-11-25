my @a=(1,2); sub f { $a[0]=9; my ($p,@r)=@_; "$p@r" } print f(@a), "\n";
