my @a=(1,2); sub w { @a=() } my @c=@a; w(); print scalar(@c),"\n";
