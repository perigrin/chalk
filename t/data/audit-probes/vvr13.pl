my @a = (1,2,3); my $r = \$a[1]; unshift @a, 0; print "$$r\n";
