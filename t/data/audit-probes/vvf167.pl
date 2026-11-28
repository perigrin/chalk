my $r = [1]; sub c { $r->[0] = 9; 0 } my @l = ($r->[0], c()); print "@l\n";
