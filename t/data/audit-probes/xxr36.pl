sub f { my ($p, $c) = @_; $c->() if $p; "$p$_[0]" } my $x = 1; print f($x, sub { $x = 5 }), "\n";
