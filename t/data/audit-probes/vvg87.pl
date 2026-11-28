my ($x, $y) = (1, 2); my $c = sub { ($x, $y) = ($y, $x) }; $c->(); print "$x$y\n";
