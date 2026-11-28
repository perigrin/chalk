my $v = 1; my $r = \$v; my $q = \$v; sub c { $$q = 9; 0 } my @l = ($$r, c()); print "@l\n";
