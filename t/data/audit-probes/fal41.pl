my $a=[1]; my $b=[2]; for (1..3) { ($a,$b)=($b,$a); push @$a,$_ } print "@$a|@$b\n";
