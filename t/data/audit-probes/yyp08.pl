my @a=(1,2); sub z { $a[1]=7; 1 } my @g = grep { z() && $_ > 3 } @a; print "@g\n";
