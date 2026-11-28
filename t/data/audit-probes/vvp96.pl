my $x = 1; sub f { $_[0] . $_[1] } print f($x = 4, $x++), "\n";
