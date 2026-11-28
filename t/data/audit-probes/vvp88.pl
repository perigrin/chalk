my $o = {i=>{v=>1}}; sub f { $_[1]{i}{v} = 5; $_[0] } print f($o->{i}{v}, $o), "\n";
