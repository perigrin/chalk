my $o = {l=>[1,2]}; sub f { my ($v, $s) = @_; $s->{l}[0] = 0; "$v$_[0]" } my @t; for my $x (@{$o->{l}}) { push @t, f($x, $o) } print "@t\n";
