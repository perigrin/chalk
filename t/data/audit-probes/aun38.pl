my ($x,$y) = (1,2); my $g = sub { "$x$y" }; ($x, $y) = ($y, $x) for 1..3; print $g->(), "\n";
