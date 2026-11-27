my @a = (1,2,3); my $c = (my ($x,$y) = @a[1,2] = (8,9)); print "$c$x$y\n";
