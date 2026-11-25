sub f { my $x = shift; eval { die "x\n" if $x; 1 } ? "ok" : "fail" } print f(0), f(1), f(0), "\n";
