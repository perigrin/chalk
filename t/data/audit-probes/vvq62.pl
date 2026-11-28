my $d = {a=>[1,2]}; my @l = (@{$d->{a}}, "x"); push @{$d->{a}}, 3; print "@l\n";
