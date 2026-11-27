sub f { my ($x) = @_; my $c = sub { $x++ }; $c->(); $c->(); $x } my $v = 1; print f($v), $v, "\n";
