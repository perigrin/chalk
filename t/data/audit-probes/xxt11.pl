my @a = (1); my $c = sub { push @a, 2; 0 }; my @l = (@a, $c->(), @a); print "@l\n";
