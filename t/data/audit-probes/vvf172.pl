my $r = \(my $v = 1); sub c { $$r = 9; 0 } my @l = ($$r, c()); print "@l\n";
