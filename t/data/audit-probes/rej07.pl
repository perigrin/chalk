my @a=("b","a"); my $c=0; my @s = sort { $c++; $a cmp $b } @a; print "@s $c\n";
