my $x = 1; my $c = sub { $x = 5; 1 }; my $r = ($x == 1 and $c->() and $x == 5) ? "y" : "n"; print "$r\n";
