sub f { my ($p) = @_; $p + 1 } sub ap { my $c = shift; $c->(@_) } my $x = 1; print ap(\&f, $x), "\n";
