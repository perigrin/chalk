my $x = 1; sub set { $x = 5 } sub f { my $n = \&set; $n->(); $_[0] } print f($x), "\n";
