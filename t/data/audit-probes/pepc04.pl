my $x=1; sub f { @_ = (5); $_[0] = 6; "@_" } print f($x), " $x\n";
