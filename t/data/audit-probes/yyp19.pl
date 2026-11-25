my @a=(1,2); my @g = grep { $a[1]=0; $_ } @a; print "@g\n";
