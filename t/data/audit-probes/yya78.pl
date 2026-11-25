my @a=(1,2,3); sub f { my ($p,$q)=@_; my @r=@_; shift; "$p$q@r@_" } print f(@a), "\n";
