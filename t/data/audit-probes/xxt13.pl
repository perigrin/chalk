my @a = (1); my $c = sub { $a[0] = 9; 0 }; my @l = (@a, $c->(), @a); print "@l\n";
