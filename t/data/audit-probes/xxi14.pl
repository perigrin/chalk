sub f { "f$_[0]" } my $n = "main::f"; print main->can("f")->(1), __PACKAGE__->can("f") ? "y" : "n", "\n";
