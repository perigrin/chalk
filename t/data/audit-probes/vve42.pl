my $x = "ab"; sub f { my $o = $_[0]; $_[0] =~ tr/a/z/; "$o$_[0]" } print f($x), "$x\n";
