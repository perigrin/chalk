sub f { wantarray ? "l" : "s" } my $c = \&f; my @a = $c->(); my $b = $c->(); my $d = &$c; print "@a$b$d\n";
