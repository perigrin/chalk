my $x=1; sub g { $_[0]=9 } sub f { my ($p)=@_; g($_[0]); $p } print f($x), "$x\n";
