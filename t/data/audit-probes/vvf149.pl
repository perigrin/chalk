my @a = (1,2,3); sub c { pop @a; 0 } my @l = ($a[0], c()); print "@l\n";
