my @a = (1,2,3); my $r = \$a[2]; my $p = pop @a; $p = 0; print "$$r\n";
