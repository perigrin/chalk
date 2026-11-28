my $x = 1; sub f { $_[0] . $_[1] } print f($x, $x = 5), "\n";
