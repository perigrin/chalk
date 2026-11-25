my @a=(1,2); sub z { $a[1]=7; 0 } my @g = map { z() + $_ } @a; print "@g\n";
