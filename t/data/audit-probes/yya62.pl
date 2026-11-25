my $x=1; sub f { my ($p,$q)=@_; "$p$q" } print f($x, $x++), "\n";
