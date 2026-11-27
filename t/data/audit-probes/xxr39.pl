sub f { my ($p, $c) = @_; $c->(); $p } my $x = 1; my $y = f($x, sub { $x = 5 }) + $x; print "$y\n";
