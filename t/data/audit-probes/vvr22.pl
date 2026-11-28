my @a = (1,2,3); my $r = \$a[2]; undef @a; print "$$r", scalar(@a), "\n";
