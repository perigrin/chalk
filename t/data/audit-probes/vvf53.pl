my $x = 1; my $c = sub { $x = 3; 2 }; print $x . $c->(), "\n";
