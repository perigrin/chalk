my @a=(1); my $f = sub { push @a, 2; 0 }; g(@a, $f->()); sub g { print scalar(@_), "\n" }
