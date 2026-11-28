my @a = (1,2,3); my $r = \$a[0]; @a = reverse @a; print "$$r\n";
