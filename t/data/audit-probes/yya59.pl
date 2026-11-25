my $x=1; sub f { my ($p)=@_; $p } sub h { $x=9 } print f($x, h()), "\n";
