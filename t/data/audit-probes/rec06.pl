our $g=1; sub f { local $g=2; my $c=shift; $c->() } eval { f(sub { die "x\n" }) }; print "$g\n";
