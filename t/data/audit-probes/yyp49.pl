my $x=1; sub f { my ($p,$i)=@_; $_[$i]=9; $p } print f($x,0), "$x\n";
