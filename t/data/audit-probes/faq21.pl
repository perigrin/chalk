my $s="k=v"; my ($k,$v); if ($s=~/(\w)=(\w)/) { ($k,$v)=($1,$2) } "zz"=~/(z)/; print "$k$v$1\n";
