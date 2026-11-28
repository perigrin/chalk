my $x = 1; sub f { my $o = $_[0]; my $r = \@_; $$r[0] = 5; "$o$_[0]" } print f($x), "$x\n";
