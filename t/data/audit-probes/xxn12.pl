our %x = (a=>1); our %y = (b=>2); sub chg { *x = \%y } chg(); print join(",", keys %x), "\n";
