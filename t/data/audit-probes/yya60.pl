my $x=1; sub f { my ($p,$q)=@_; "$p$q" } sub h { $x=9; 0 } print f($x, h()), "\n";
