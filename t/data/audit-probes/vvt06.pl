my @a = (1,2,3); sub f { @a = (7,8,9); 0 } my @o; for my $i (0..2) { push @o, $a[$i]; f() if $i == 0 } print "@o\n";
