my @a = (1); my $c = sub { @a = (7, 8) }; my @o = @a; $c->(); print "@o|@a\n";
