our $x=1; my $r=\$x; { local $x=2; print "$$r $x\n" } print "$$r $x\n";
