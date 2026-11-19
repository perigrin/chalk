my @a = (1,2); my $e = \$a[0]; @a = (3,4); print "$$e $a[0]\n";
