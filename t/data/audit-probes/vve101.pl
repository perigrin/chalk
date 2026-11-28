my $o = {v=>1}; sub f { $o->{v} = 5; $_[0] } print f($o->{v}), "\n";
