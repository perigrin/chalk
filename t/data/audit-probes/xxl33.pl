my ($p,$q) = (1,1); my @f; while (@f < 6) { push @f, $p; ($p,$q) = ($q, $p + $q) } print "@f\n";
