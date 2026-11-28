my $x = 1; sub f { $x = 5; join ",", @_ } print f($x, $x), "\n";
