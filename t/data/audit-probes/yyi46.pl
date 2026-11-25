sub f { my $n = shift; return $n ? $n + f($n-1) : 0 } sub ev { $_[0] == 0 ? 1 : od($_[0]-1) } sub od { $_[0] == 0 ? 0 : ev($_[0]-1) } print f(10), ev(10), od(7), "\n";
