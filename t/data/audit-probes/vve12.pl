my $x = 1; sub f { eval '$x = 5'; $_[0] } print f($x), "\n";
