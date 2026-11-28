my @a = map { $_->[0] } sort { $a->[1] <=> $b->[1] or $a->[0] cmp $b->[0] } map { [$_, length] } qw(bb a cc); print "@a\n";
