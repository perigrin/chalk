our ($p,$q) = (1,2); *p = \$q; for ($p) { $_ = 7 } print "$q\n";
