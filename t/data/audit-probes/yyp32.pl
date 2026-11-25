my $x="ab"; sub f { my ($p)=@_; $_[0] x= 2; $p } print f($x), "$x\n";
