my @a = (1,2,3); my $r = \$a[1]; @a = (@a); $a[1] = 7; print "$$r\n";
