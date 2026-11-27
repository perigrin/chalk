my ($x,$y) = (1,2); my $r = \$x; for my $i (1..4) { $$r += $i; $r = $i % 2 ? \$y : \$x } print "$x $y\n";
