my $o = {l=>[1,2]}; sub f { $_[1]{l}[0] = 0; $_[0] } my @t; for my $x (@{$o->{l}}) { push @t, f($x, $o) } print "@t\n";
