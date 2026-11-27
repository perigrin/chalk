my @a=(1); sub pa { push @a, 2 } my @l = (scalar(@a), pa(), scalar(@a), "@a"); print "@l\n";
