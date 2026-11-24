my @a=(1,2); sub w { $a[0]=9 } sub f { my @c=@a; w(); "@c" } print f(),"\n";
