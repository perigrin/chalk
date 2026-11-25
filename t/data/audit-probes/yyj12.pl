my @c; for my $i (1..3) { $c[$i] = sub { $i * 2 } } print $c[1]->(), $c[3]->(), "\n";
