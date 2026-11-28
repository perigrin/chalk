my @a = map { [$_, $_ * 2] } 1..3; my @b = map { $_->[1] } grep { $_->[0] > 1 } @a; print "@b\n";
