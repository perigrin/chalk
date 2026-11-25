my ($a1,$b1)=(1,2); my $c=1; ($c ? $a1 : $b1) = 9; my $f=sub { "$a1$b1" }; print $f->(),"\n";
