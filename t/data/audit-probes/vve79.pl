my $x = 1; sub f { $x = 5; goto &g } sub g { $_[0] } print f($x), "\n";
