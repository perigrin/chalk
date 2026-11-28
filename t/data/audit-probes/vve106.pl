my $o = [1]; sub f { my ($v, $r) = @_; @$r = (5); $v } print f($o->[0], $o), "\n";
