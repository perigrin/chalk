my %h = (a=>1); sub f { $h{a} = 0; $_[0] } my @t; for my $v (values %h) { push @t, f($v) } print "@t\n";
