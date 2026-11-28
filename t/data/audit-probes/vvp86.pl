my $o = {v=>1}; my @os = ($o); sub f { $_->{v} = 5 for @os; $_[0] } print f($o->{v}), "\n";
