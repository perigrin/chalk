my @f; for (1..3) { my $c=$_*10; push @f, sub { $c += shift } } $f[0]->(1); print $f[0]->(1), $f[1]->(0), "\n";
