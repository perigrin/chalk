sub f { wantarray ? "l" : "s" } sub g { f() if $_[0] } sub h { $_[0] ? f() : f() } my @a = g(1); my $b = g(1); my @c = h(0); print "@a$b@c\n";
