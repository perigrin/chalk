my $a1 = [1]; my $a2 = [2]; ($a1, $a2) = ($a2, $a1); push @$a1, 9; print "@$a1|@$a2\n";
