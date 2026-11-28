our $x = 1; sub f { local $x = $_[0]; \$x } my $r = f(5); print "$$r$x\n";
