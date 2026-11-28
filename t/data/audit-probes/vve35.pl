my $x = 1; sub f { my $o = $_[0]; my $r = \$_[0]; $$r = 5; "$o$_[0]" } print f($x), "$x\n";
