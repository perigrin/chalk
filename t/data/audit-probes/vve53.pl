my $x = 1; sub f { local $_[0] = 5; $_[0] } print f($x), "$x\n";
