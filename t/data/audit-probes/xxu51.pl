our $x = 1; sub c { $x = 3; 2 } my @a = (10,20,30,40); $a[c()] = $x; print "@a\n";
