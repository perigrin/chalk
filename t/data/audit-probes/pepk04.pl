our $x=1; my $r; { local $x=2; $r=\$x } $$r=5; print "$$r $x\n";
