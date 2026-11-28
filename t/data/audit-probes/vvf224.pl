our %t = (a=>1, b=>5); our $k = "a"; sub c { $k = "b"; 2 } my @l = ($t{$k}, c()); print "@l\n";
