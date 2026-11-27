my $x = 1; my $c = sub { $x = 5; 0 }; my $r = $x > 0 ? $c->() + $x : $x; print "$r\n";
