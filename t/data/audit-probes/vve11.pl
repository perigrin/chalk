my $x = 1; sub set { $x = 5 } sub f { my $m = "set"; main->$m; $_[0] } print f($x), "\n";
