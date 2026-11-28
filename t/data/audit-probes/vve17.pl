our $x = 1; sub f { my $g = \*x; ${*$g} = 5; $_[0] } print f($x), "\n";
