my @a=(1,2); my @f; for my $x (@a) { push @f, sub { $x*=10 } } $_->() for @f; print "@a\n";
