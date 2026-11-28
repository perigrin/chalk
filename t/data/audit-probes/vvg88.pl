my ($x, $y) = (1, 2); my $c = sub { $x + $y }; ($x, $y) = (3, 4); print $c->(), "\n";
