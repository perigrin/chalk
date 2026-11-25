my @f; for my $i (1..3) { my $k=$i*2; push @f, sub { $k++ } } $f[0]->(); print join("", map { $_->() } @f), "\n";
