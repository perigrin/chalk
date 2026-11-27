our $x = 7; sub c { $x = 9; 2 } my $s = ($x % c()) . ($x / c()); print "$s\n";
