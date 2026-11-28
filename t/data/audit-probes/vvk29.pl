sub f { wantarray ? "l" : "s" } sub g { for (1) { return f() } } my @a = g(); my $b = g(); print "@a$b\n";
