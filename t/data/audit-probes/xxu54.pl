our $x = 1; sub c { $x = 3; 2 } my ($p, $q) = ($x, c()); print "$p$q\n";
