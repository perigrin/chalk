sub f { my ($p, $c) = @_; my $i = 0; while ($i++ < 2) { $c->() } "$p$_[0]" } my $x = 1; print f($x, sub { $x++ }), "\n";
