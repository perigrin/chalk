sub f { my ($p,$r) = @_; $$r = 5; "$p$_[0]" } my $x = 1; print f($x, \$x), "\n";
