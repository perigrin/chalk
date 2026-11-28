sub f { wantarray ? "l" : "s" } sub g { &f } sub h { goto &f } my @a = g(); my $b = h(); print "@a$b\n";
