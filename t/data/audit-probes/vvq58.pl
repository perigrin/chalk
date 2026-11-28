my %h = (a=>[1,2]); my $n = (() = (@{$h{a}}, "x")); push @{$h{a}}, 3; print "$n\n";
