my @a = (1); my $c = sub { push @a, 2 }; my $o = scalar(@a); $c->(); print $o, scalar(@a), "\n";
