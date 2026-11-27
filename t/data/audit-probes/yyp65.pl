my @a=(1,2); sub f { unshift @a, 0; my ($p,$q)=@_; "$p$q" } print f(@a), "\n";
