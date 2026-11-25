my $s="aaa"; my $n=0; $n++ while $s=~/a/g; print "$n", pos($s) // "u", "\n";
