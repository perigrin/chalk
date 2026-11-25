my $x=1; sub f { my ($p,$q)=@_; $_[0]=5; my ($r)=@_; "$p$q$r" } print f($x,2), "\n";
