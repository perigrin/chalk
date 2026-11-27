my $x = 1; my $c = sub { $x = 5; 1 }; my $v = $x; $c->(); print $v + $x, "\n";
