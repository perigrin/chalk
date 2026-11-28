my $x = 1; sub c { $x = 7; 0 } my @l = ($x = 4, c()); print "@l\n";
