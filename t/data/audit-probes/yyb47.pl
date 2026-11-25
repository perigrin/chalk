my @a=(1,2); sub z { @a=(5,6) } my @g = map { $_ * 2 } @a; z(); print "@g @a\n";
