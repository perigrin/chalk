sub f { my ($r) = @_; my $s = $r; $s->[0] = 9; my @c = @$r; $c[1] = 8; "@$r" } my @a=(1,2); print f(\@a), "|@a\n";
