our @g = (1,2); sub cp { my @c = (@g, 0); @g = (); return scalar @c } print cp(), scalar(@g), "\n";
