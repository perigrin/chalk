my $x=1; sub f { shift; scalar @_ } print f($x,2), "\n";
