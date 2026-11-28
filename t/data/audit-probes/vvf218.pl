our @t = (1); sub c { @t = (7,8); 2 } my @l = (scalar(@t), c()); print "@l\n";
