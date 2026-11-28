sub f { wantarray ? "l" : "s" } my $x = f() ? f() : 0; my @y = (1 ? f() : 0); my $z = (f(), f())[1]; print "$x@y$z\n";
