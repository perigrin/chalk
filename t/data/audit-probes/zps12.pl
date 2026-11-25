my @a=("a","b"); for my $x (@a) { $x=~s/a/z/ if $x eq "a" } print "@a\n";
