my ($x, $y); my $r = \$x; my @l = ((($x, $y) = (7,8)), $$r = 9); print "@l\n";
