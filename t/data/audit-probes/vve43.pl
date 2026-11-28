my $x = "ab"; sub f { my $o = $_[0]; chop $_[0]; "$o$_[0]" } print f($x), "$x\n";
