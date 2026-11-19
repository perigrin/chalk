my $x = 5; my ($p, $q) = (\$x, \$x); $$p = 6; print "$$q\n";
