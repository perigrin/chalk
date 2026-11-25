sub f { my $x = shift // 5; my $y = shift || 7; my $z = @_ ? shift : 9; "$x$y$z" } print f(), f(0,0,0), f(undef,undef,undef), f(1,2,3), "\n";
