my @a = (1,2,3); my @c; for my $e (@a) { push @c, sub { $e *= 2 } } $_->() for @c; print "@a\n";
