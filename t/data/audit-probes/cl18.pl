my $x = 1; my $g = sub { $x }; my $r = \$x; $$r = 4; print $g->(), "\n";
