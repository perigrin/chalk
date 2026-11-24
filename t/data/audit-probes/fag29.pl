my @a=(1,2); sub w { pop @a } my @c=@a; w(); print scalar(@c), scalar(@a), "\n";
