my $o = {i=>{v=>1}}; sub f { $_[1]{v} = 5; $_[0] } print f($o->{i}{v}, $o->{i}), "\n";
