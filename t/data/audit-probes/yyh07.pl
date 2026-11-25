sub c { wantarray ? "L" : "S" } sub f { "@_" } my ($x) = c(); my @a; push @a, c(); print f(c()), $x, "@a\n";
