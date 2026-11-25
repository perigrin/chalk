sub f { my $x = shift; $x > 1 and return "big"; "small" } sub g { $_[0] || return "none"; "some" } print f(1), f(2), g(0), g(1), "\n";
