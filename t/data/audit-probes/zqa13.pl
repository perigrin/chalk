my ($x,$y)=(1,2); sub f { my ($p,$q)=@_; $_[0]=9; "$p$q" } print f($x,$y), "$x\n";
