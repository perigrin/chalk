my %h = (a=>[1,2]); my ($p, $q, $t) = (@{$h{a}}, "x"); push @{$h{a}}, 3; print "$p$q$t\n";
