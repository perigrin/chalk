sub depth { my $t=shift; ref $t ? 1 + (sort { $b <=> $a } map { depth($_) } @$t, 0)[0] : 0 } print depth([1,[2,[3]],[4]]), "\n";
