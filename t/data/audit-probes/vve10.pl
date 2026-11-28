my $x = 1; sub set { $x = 5 } sub f { main->set; $_[0] } print f($x), "\n";
