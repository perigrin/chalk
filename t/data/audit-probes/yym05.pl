my @recs = map { { n => $_, k => $_ % 3 } } 1..9; my @s = sort { $a->{k} <=> $b->{k} } @recs; print join("", map { $_->{n} } @s), "\n";
