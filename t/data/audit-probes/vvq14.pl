my $v = 1; my $r = \$v; my @l = ($$r, $v = 9); print "@l\n";
