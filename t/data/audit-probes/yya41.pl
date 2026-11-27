my $x=1; sub f { my ($p)=@_; my $r=\$_[0]; $$r=9; $p } print f($x), "$x\n";
