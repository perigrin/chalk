my $n = 0; sub f { $n++; die "f\n" } sub g { f(); $n += 10 } eval { g() }; print "$n\n";
