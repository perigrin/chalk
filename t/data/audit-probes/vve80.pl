my $x = 1; sub f { $x++; g($_[0]) } sub g { $x++; h($_[0]) } sub h { $_[0] } print f($x), "\n";
