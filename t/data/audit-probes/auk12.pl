eval { foreach my $x (1) { if ($x) { die "in\n" } } }; print "[$@]\n";
