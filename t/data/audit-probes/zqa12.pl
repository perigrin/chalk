my @a=(1,2); sub f { my ($p,$q)=@_; $_[1]=9; "$p$q" } print f(@a), "@a\n";
