my @a = (1); my $c = sub { $a[0] = 5 }; my $o = $a[0]; $c->(); print $o, $a[0], "\n";
