my $x = 1; my $c = sub { $x = 5; 1 }; if ($x == 1 && $c->() && $x == 1) { print "a\n" } else { print "b\n" }
