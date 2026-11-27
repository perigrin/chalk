sub f { my ($p,$r) = @_; $r->[0] = 5; "$p$_[0]" } my @a = (1); print f($a[0], \@a), "\n";
