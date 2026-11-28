my %h = (k=>1); sub c { $h{k} = 9; 0 } my @l = (@h{"k"}, c()); print "@l\n";
