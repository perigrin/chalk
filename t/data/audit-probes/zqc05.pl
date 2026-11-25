my @a=(1,2); sub z { $a[1]=7 } print map { z(); $_ } @a; print "\n";
