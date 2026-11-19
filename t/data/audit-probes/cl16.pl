my $x; my $g = sub { $x // "u" }; $x = 5; undef $x; print $g->(), "\n";
