my @a=(1,2,3); my @r = map { $_*2 } grep { $_%2 } @a; print "@r\n";
