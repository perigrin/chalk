my @a = (1, undef, 3); my $c = grep { defined } @a; my @d = map { $_ // 0 } @a; print "$c@d\n";
