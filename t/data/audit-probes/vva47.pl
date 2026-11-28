our $x = 1; my $r; { local $x = 2; $r = \$x } print "$$r$x\n";
