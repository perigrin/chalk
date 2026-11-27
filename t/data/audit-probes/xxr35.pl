sub f { my ($p, $c) = @_; eval { $c->() }; "$p$_[0]" } my $x = 1; print f($x, sub { $x = 5; die "z\n" }), "\n";
