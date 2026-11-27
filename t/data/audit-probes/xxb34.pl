my @a=(1,2,3); my @c; for my $x (@a) { push @c, sub { $x++ } } $_->() for @c; print "@a\n";
