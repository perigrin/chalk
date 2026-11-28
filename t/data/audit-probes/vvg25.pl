my @a = (1,2,3); my $r = \$a[1]; @a = (4,5,6); print "$$r@a\n";
