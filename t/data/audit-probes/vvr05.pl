my @a = (1,2,3); my $r = \$a[0]; @a = (reverse @a); $a[2] = 7; print "$$r\n";
