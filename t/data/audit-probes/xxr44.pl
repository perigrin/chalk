sub f { my $n = shift; my $c = shift; $c->(); "$n$main::keep" } our $keep = "k"; my $x = 1; print f($x, sub { $x = 5; $keep = $x }), "\n";
