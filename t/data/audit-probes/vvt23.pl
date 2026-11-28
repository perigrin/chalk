my $r = [1,2,3]; sub f { $_[0] .= "x" } for my $x (@$r) { f($x) } print "@$r\n";
