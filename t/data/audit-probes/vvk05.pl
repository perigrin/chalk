sub f { $_[0] = "n" } my $r = [1]; f($r->[0]); f($$r[1]); print "@$r\n";
