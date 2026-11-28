my $v = 1; my $r = \$v; my @l = ($v, $$r = 9); print "@l\n";
