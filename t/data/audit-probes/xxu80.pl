our %x = (k=>1); sub c { $x{j} = 3; 2 } my @l = (scalar(keys %x), c()); print "@l\n";
