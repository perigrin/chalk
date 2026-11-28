sub f { my $x = shift // 9; my $y = shift || 8; "$x$y" } print f(), f(0, 0), f(1, 2), "\n";
