my $x = 1; sub f { ($_[0], my $t) = (5, 6); $_[0] } print f($x), "$x\n";
