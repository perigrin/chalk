my $x; sub f { $_[0] //= 8; $_[0] } print f($x), "$x\n";
