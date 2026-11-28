my $x = "ab\n"; sub f { chomp @_; $_[0] } print f($x), "$x\n";
