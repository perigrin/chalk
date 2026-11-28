our $x = 1; my ($p, $q) = (3, 4); *x = 1 ? \$p : \$q; $x = 0; print "$p$q\n";
