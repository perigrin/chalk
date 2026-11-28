my $v = 1; my $r = \$v; my @l = ($$r, $v++); print "@l\n";
