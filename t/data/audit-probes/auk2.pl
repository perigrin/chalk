eval { for my $x (1,2) { die "m$x\n" if $x == 2 } }; print "[$@]\n";
