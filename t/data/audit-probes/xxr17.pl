my $x = 1; sub setx { $x = 5 } sub f { my $o = $_[0]; my $n = "setx"; main->$n(); "$o$_[0]" } print f($x), "\n";
