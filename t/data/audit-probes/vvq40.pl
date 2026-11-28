my $o = [1]; my $p = $o; sub c { $o->[0] = 9; 0 } my @l = ($p->[0], c()); print "@l\n";
