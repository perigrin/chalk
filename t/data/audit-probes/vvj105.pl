my @a = sort { $a->[1] <=> $b->[1] } map { [$_, length $_] } qw(ccc a bb); print join(",", map { $_->[0] } @a), "\n";
