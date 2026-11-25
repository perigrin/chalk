my $x=1; sub f { my ($p)=@_; $_[0]=9; $p } print f($x+0), "$x\n";
