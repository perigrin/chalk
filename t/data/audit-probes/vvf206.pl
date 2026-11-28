our $x = 1; sub c { $x = 3; 2 } my @l = ((my $t = $x), c()); print "@l\n";
