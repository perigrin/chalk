my $o = {v=>1}; sub f { $_[1]{v} = 0; $_[0] } my @t; for my $x ($o->{v}) { push @t, f($x, $o) } print "@t\n";
