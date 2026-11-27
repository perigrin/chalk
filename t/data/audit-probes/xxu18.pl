our $x = 1; sub c { $x = 3; 2 } my @l = sort { $a <=> $b } ($x, c()); print "@l\n";
