sub f { my $r = $_[0] ? "yes" : "no" } sub g { my $x = 5; $x += $_[0] } sub h { my @a = @_; push @a, 1 } print f(1), g(2), h(7,8), "\n";
