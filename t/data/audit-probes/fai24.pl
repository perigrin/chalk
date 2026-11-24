my ($a,$b)=(1,2); my $c=1; ($c ? $a : $b) = ($c ? $b : $a) + 5; print "$a$b\n";
