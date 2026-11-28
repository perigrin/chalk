my $o = {v=>1}; sub f { my %c = (r => $o); $c{r}{v} = 5; $_[0] } print f($o->{v}), "\n";
