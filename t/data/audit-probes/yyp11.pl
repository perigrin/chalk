my @a=(1,2); sub z { $a[1]=7 } my @g = map { z(); $_ * 2 } @a; print "@g\n";
