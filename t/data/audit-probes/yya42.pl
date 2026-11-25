my $x=1; sub f { my $r=\$_[0]; my ($p)=@_; $$r=9; "$p$_[0]" } print f($x), "$x\n";
