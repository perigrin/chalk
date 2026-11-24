my $o={n=>1}; sub f { $o->{n}=2; $_[0] } print f($o->{n}),"\n";
