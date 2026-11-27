our $x = 1; sub c { $x = 3; 2 } my ($p, $q); ($p, $q) = (c(), $x); ($q, $p) = ($x, c()); print "$p$q\n";
