my @a = (1); my $c = sub { $a[0] = 9; 0 }; my @l = ($a[0], $c->(), $a[0]); print "@l\n";
