my $x = 1; sub f { my $v = shift; $v++; $_[0] } print f($x, 7), "$x\n";
