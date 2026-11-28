my %h = (k=>1); sub c { $h{j} = 9; 0 } my @l = (scalar(keys %h), c()); print "@l\n";
