sub f { my ($p) = @_; my $c = pop; $c->(); "$p$_[0]" } my $x = 1; print f($x, sub { $x = 5 }), "\n";
