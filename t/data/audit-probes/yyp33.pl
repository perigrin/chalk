my $x=0; sub f { my ($p)=@_; $_[0] ||= 5; $p } print f($x), "$x\n";
