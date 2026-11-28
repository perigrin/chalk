my $o = [1]; sub f { my ($v, $r) = @_; $r->[0] = 5; "$v$_[0]" } print f($o->[0], $o), "\n";
