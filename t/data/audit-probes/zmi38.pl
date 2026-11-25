my @a=(3,10,2); print join(",", sort @a), "|", join(",", sort { $a <=> $b } @a), "|", join(",", reverse sort { $a <=> $b } @a), "|", join(",", sort { $b cmp $a } @a), "\n";
