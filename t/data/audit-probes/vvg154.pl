my @a = ({n=>1}, {n=>2}); my %by = map { $_->{n} => $_ } @a; $by{2}{n} = 9; print $a[1]{n}, "\n";
