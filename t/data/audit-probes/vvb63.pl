my @c = map { my $x = $_; (sub { $x++ }, sub { $x }) } 1..2; $c[0]->(); print $c[1]->(), $c[3]->(), "\n";
