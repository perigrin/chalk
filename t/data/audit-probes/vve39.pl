my $x = 1; sub f { my $o = $_[0]; map { $_++ } @_; "$o$_[0]" } print f($x), "$x\n";
