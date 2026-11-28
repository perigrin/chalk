my $x = 1; sub f { my $o = $_[0]; for (@_) { $_ = 5 } "$o$_[0]" } print f($x), "$x\n";
