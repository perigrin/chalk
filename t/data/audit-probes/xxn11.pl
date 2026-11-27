our $x = 1; sub rd { $x } sub chg { *x = \42 } my @l = (rd(), chg() && rd()); print "@l\n";
