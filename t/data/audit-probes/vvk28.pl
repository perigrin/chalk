sub f { wantarray ? "l" : "s" } sub g { my $r = f(); $r } sub h { my ($r) = f(); $r } print g(), h(), "\n";
