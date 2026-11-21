my $r = [1, 2]; sub f { $_ = 9 for @$r; "" } print $r->[0], f(), "\n";
