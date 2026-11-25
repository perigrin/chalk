my $x=1; sub f { my ($p)=@_; $p=9; $_[0] } print f($x), "$x\n";
