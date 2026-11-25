my $x = "outer"; sub f { my $x = "f"; g() } sub g { $x } print f(), "\n";
