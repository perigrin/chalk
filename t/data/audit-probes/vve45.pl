my $x = "ab"; sub f { substr($_[0], 0, 1) = "z"; $_[0] } print f($x), "$x\n";
