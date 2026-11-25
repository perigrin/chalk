my @c; for (my $i=0; $i<3; $i++) { push @c, sub { $i } } print map({ $_->() } @c), "\n";
