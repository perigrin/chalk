sub c { wantarray ? "L" : "S" } sub g { return (c())[0] } sub h { return scalar(c()) } my @x = g(); my @y = h(); my $z = g(); print "@x@y$z\n";
