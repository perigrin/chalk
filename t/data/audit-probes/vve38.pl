my $x = 1; sub f { my $o = $_[0]; $_++ for @_; "$o$_[0]" } print f($x), "$x\n";
