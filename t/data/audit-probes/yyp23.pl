my @a=(1,2,3); sub z { $_[0]=7 } my @g = map { z($a[2]); $_ } @a; print "@g\n";
