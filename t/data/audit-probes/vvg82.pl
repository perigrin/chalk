my @a = (1); my $c = sub { push @a, 2 }; my $o = "@a"; $c->(); print "$o|@a\n";
