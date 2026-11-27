sub f { $_[1]->(); my $p = $_[0]; "$p" } our $x = 1; print f($x, sub { $x = 5 }), "\n";
