my @a=(1,2,3); my @g = map { $_ } grep { $_-- > 1 } @a; print "@g\n";
