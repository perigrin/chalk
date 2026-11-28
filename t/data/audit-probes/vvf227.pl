our $o = [[1]]; sub c { $o->[0][0] = 7; 2 } my @l = ($o->[0][0], c()); print "@l\n";
