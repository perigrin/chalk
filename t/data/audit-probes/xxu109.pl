our $x = 1; sub c { $x = 3; 2 } sub lv :lvalue { $x } my @l = (lv(), c()); print "@l\n";
