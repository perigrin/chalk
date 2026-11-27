our $x = 1; sub c { $x = 3; 2 } my $s = sprintf("%d-%d", $x, c()); print "$s\n";
