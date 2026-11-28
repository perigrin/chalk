my $x = 1; sub c { $x = 7; 0 } my @l = (++$x, c()); print "@l\n";
