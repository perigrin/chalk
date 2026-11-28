my $x = 1; my $c = sub { $x = 5 }; sub f { $c->(); $_[0] } print f($x), "\n";
