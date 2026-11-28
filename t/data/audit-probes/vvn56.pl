my ($a1, $b1); for my $i (1..2) { if ($i == 1) { $a1 = \$i } else { $b1 = \$i } } $$a1 = 7; print "$$a1$$b1\n";
