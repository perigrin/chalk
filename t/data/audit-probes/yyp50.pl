my $x=1; sub f { my ($p)=@_; $_[-1]=9; $p } print f($x), "$x\n";
