my $x = 1; my $c = sub { $x++; () }; my @a = ([$x], $c->(), [$x]); print $a[0][0], $a[1][0], "\n";
