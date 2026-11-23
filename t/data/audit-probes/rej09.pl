my $x="5 apples"; { no warnings; my $n=$x+0; $x="k"; print "$n $x\n"; }
