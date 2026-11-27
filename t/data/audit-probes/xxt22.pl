my $x = 1; my $c = sub { $x = 5; 1 }; my @a = (10,20,30,40,50,60); my @l = @a[$x, $c->(), $x]; print "@l\n";
