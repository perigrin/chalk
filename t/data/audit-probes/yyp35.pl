my $x=2; sub f { my ($p)=@_; $_[0] **= 2; --$_[0]; $p } print f($x), "$x\n";
