my @a = ({n=>1}, {n=>2}); $_->{n} *= 2 for @a; print join(",", map { $_->{n} } @a), "\n";
