my $o = {i=>{v=>1}}; my $in = $o->{i}; sub f { $in->{v} = 5; $_[0] } print f($o->{i}{v}), "\n";
