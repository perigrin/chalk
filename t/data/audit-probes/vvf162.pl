my %h = (k=>1); sub c { delete $h{k}; 0 } my @l = (exists $h{k} ? 1 : 0, c()); print "@l\n";
