my ($x,$y)=(1,2); sub f { my ($p,$q)=@_; @_[0,1]=(8,9); "$p$q" } print f($x,$y), "$x$y\n";
