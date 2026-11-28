sub f { wantarray ? "l" : "s" } sub g { eval { f() } } sub h { do { f() } } my @a = g(); my $b = h(); print "@a$b\n";
