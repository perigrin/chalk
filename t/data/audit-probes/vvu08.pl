my $x = 1; sub lv :lvalue { $x } my $m = "lv"; sub f { $x = 7; $_[0] } print main->$m() . f(main->$m()), "\n";
