my %h = (a=>1); sub f { $h{a} = 0; $_[0] } my @t; for my $k (keys %h) { push @t, f($h{$k}) } print "@t\n";
