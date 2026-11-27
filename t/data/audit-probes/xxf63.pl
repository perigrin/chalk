$_ = "t"; sub f { local $_ = "f"; g2() } sub g2 { $_ } print f(), $_, "\n";
