eval { for my $x (1) { g() } }; sub g { die "g\n" } print "[$@]\n";
