my @a=("x"); sub w { $a[0].="y" } my @c=@a; w(); w(); print "@c @a\n";
