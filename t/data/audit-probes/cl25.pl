my $x = 5; my $g = sub { $x }; my $s = "v=5"; ($x) = $s =~ /(\d)/ ? 6 : 0; print $g->(), "\n";
