my @a=(5,3,9); my ($i)=grep { $a[$_]==9 } 0..$#a; my $first=(grep { $_>4 } @a)[0]; my $cnt=grep { $_>4 } @a; print "$i$first$cnt\n";
