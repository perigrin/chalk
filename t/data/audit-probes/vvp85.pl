my $o = {v=>1}; my @os = ($o); sub f { $os[0]{v} = 5; $_[0] } print f($o->{v}), "\n";
