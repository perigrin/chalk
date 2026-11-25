my $x=1; sub g { $_[0]=9 } sub f { &g; my ($p)=@_; $p } print f($x), "$x\n";
