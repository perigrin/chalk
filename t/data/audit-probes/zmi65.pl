my @a=(1,2,3); my $s=0; $s+=$_ for @a; my $p=1; $p*=$_ for @a; my $j=join "+", @a; print "$j=$s $p\n";
