my @a = (1,2); sub f { $a[-2] = 5; $_[0] } my $i = 0; print f($a[$i]), "\n";
