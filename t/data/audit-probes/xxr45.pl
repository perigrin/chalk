sub f { my ($p, $c) = @_; $c->($p); "$p$_[0]" } my $x = 1; print f($x, sub { $x = $_[0] + 4 }), "\n";
