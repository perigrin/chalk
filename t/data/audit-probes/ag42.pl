my $r = [1, 2]; sub f { shift @$r; "" } print $r->[0], f(), "\n";
