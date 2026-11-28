my $x = 1; sub lv :lvalue { $x } my $m = "lv"; my @l = (main->$m(), ($x = 5)); print "@l\n";
