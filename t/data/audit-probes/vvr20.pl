my @a = (1,2,3); my $r = \$a[2]; $#a = 0; print "$$r", scalar(@a), "\n";
