my ($a,$b)=(1,2); my $c=1; my $r=\($c ? $a : $b); $$r=9; print "$a$b\n";
