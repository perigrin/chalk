my $x = 1; my $g = sub { $x }; ($x, my @rest) = (5, 6); print $g->(), "\n";
