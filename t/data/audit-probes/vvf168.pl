my $r = [1]; sub c { $r->[0] = 9; 0 } my @l = (@$r, c()); print "@l\n";
