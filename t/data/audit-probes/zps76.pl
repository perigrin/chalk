my @f; my $j=0; for my $i (1..3) { $j=$i; push @f, sub { $j } } print join("", map { $_->() } @f), "\n";
