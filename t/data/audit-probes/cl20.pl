my $x = 1; my $g = sub { $x }; $x ||= 9; $x &&= 3; $x //= 4; print $g->(), "\n";
