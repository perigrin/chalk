my %h = (k=>1); sub c { $h{k} = 9; 0 } my @l = (%h, c()); print "@l\n";
