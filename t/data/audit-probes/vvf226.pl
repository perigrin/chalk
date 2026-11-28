our $o = {v => 1}; sub c { $o->{v} = 7; 2 } my @l = ($o->{v}, c()); print "@l\n";
