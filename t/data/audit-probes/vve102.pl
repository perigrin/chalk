my $o = {v=>1}; my $p = $o; sub f { $p->{v} = 5; $_[0] } print f($o->{v}), "\n";
