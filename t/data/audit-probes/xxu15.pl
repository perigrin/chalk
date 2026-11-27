our $x = 1; sub c { $x = 3; 2 } my $s = substr("abcdef", $x, c()); print "$s\n";
