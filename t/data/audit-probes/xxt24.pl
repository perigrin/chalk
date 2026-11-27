my ($x,$y) = (1,2); my $c = sub { ($x,$y) = ($y,$x); 0 }; my @l = ($x, $y, $c->(), $x, $y); print "@l\n";
