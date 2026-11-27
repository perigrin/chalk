my $n = 0; my @c = map { my $k = $_; sub { $n += $k } } 1..3; $_->() for @c; print "$n\n";
