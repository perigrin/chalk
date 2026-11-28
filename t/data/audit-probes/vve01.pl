sub f { $_[1]->(); $_[0] } my $x = 1; print f($x, sub { $x = 5 }), "\n";
