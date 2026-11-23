my @a=(1); my $f = sub { push @a, 2; 0 }; my @c = (@a, $f->()); print "@c\n";
