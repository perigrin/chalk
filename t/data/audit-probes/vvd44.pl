my ($p, $q) = (0, 1); ($p, $q) = ($q, $p + $q) for 1..10; print "$p\n";
