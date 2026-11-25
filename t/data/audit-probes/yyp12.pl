my @a=(1,2); sub z { $a[1]=7 } my @g = map { $_ * 2 } map { z(); $_ } @a; print "@g\n";
