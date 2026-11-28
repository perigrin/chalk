my @a = (1,2,3); my $r = \$a[1]; $a[1] = 9; print "$$r\n";
