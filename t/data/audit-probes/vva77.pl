our $x = 1; print "a" if do { local $x = 0; !$x }; print "$x\n";
