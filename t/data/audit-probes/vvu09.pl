my $x = 1; sub lv :lvalue { $x } my $m = "lv"; sub f { $x = 7; print $_[0], "\n" } f(main->$m());
